const express = require('express');
const pam = require('authenticate-pam');
const jwt = require('jsonwebtoken');
const helmet = require('helmet');
const { execFile } = require('child_process');
const fs = require('fs');
const fsp = require('fs/promises');
const http = require('http');
const https = require('https');
const path = require('path');
const os = require('os');
const crypto = require('crypto');

const app = express();

const PORT_HTTP = 3000;
const PORT_HTTPS = 443;

const APP_ROOT = path.join(__dirname, '..');
const PUBLIC_DIR = path.join(APP_ROOT, 'public');
const CAPTURE_DIR = '/var/lib/spiffer/captures';
const JWT_EXPIRES_IN = '10m';
const TSHARK_BIN = 'tshark';
const CAPTURE_INTERFACE = process.env.SPIFFER_CAPTURE_INTERFACE || 'br0';
const CERT_DIR = '/etc/spiffer/certs';

function loadHttpsOptions() {
  const keyPath = path.join(CERT_DIR, 'server.key');
  const certPath = path.join(CERT_DIR, 'server.crt');

  if (!fs.existsSync(keyPath)) {
    throw new Error(`HTTPS private key not found: ${keyPath}`);
  }

  if (!fs.existsSync(certPath)) {
    throw new Error(`HTTPS certificate not found: ${certPath}`);
  }

  return {
    key: fs.readFileSync(keyPath),
    cert: fs.readFileSync(certPath),
  };
}

const httpsOptions = loadHttpsOptions();

// In-memory state
let captureInProgress = false;

// Ensure runtime folders exist
fs.mkdirSync(CAPTURE_DIR, { recursive: true });

// JWT secret generated at startup
const SECRET_KEY = crypto.randomBytes(64).toString('hex');

// ---------- Helpers ----------

function jsonSuccess(res, message, data = {}, status = 200) {
  return res.status(status).json({
    success: true,
    message,
    data,
  });
}

function jsonError(res, status, error, details = undefined) {
  return res.status(status).json({
    success: false,
    error,
    ...(details ? { details } : {}),
  });
}

function getServerAddresses() {
  const interfaces = os.networkInterfaces();
  const addresses = [];

  for (const [name, ifaceAddresses] of Object.entries(interfaces)) {
    if (!Array.isArray(ifaceAddresses)) continue;

    for (const address of ifaceAddresses) {
      if (address.family === 'IPv4' && !address.internal) {
        addresses.push({
          interface: name,
          address: address.address,
        });
      }
    }
  }

  return addresses;
}

function verifyToken(req, res, next) {
  const authHeader = req.headers.authorization || '';
  const [scheme, token] = authHeader.split(' ');

  if (scheme !== 'Bearer' || !token) {
    return jsonError(res, 403, 'Missing or invalid Authorization header');
  }

  jwt.verify(token, SECRET_KEY, (err, decoded) => {
    if (err) {
      return jsonError(res, 401, 'Invalid or expired token');
    }

    req.user = decoded;
    next();
  });
}

function isValidCaptureName(filename) {
  return /^[a-zA-Z0-9_-]+$/.test(filename);
}

function isValidCaptureFormat(format) {
  return ['pcap', 'pcapng'].includes(format);
}

function isValidDelayUnit(unit) {
  return ['seconds', 'minutes'].includes(unit);
}

function buildHttpsRedirectHost(hostHeader) {
  if (!hostHeader) {
    return `localhost:${PORT_HTTPS}`;
  }

  const hostOnly = hostHeader.replace(/:\d+$/, '');
  return `${hostOnly}:${PORT_HTTPS}`;
}

function buildCaptureFilePath(baseName, format) {
  const safeName = path.basename(baseName);
  return path.join(CAPTURE_DIR, `${safeName}.${format}`);
}

function isApiRequest(req) {
  return req.path.startsWith('/api/');
}

async function listCaptureFiles() {
  const files = await fsp.readdir(CAPTURE_DIR, { withFileTypes: true });
  return files
    .filter((entry) => entry.isFile())
    .map((entry) => entry.name)
    .sort((a, b) => a.localeCompare(b));
}

function runTsharkCapture({ outputFile, durationInSeconds }) {
  return new Promise((resolve, reject) => {
    const args = [
      '-i',
      CAPTURE_INTERFACE,
      '-a',
      `duration:${durationInSeconds}`,
      '-w',
      outputFile,
    ];

    execFile(TSHARK_BIN, args, (error, stdout, stderr) => {
      if (error) {
        error.stdout = stdout;
        error.stderr = stderr;
        return reject(error);
      }

      return resolve({ stdout, stderr });
    });
  });
}

// ---------- Middleware ----------

// Security headers
app.use(
  helmet({
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        scriptSrc: ["'self'"],
        styleSrc: ["'self'", "'unsafe-inline'"],
        imgSrc: ["'self'", 'data:'],
        connectSrc: ["'self'"],
        frameAncestors: ["'none'"],
      },
    },
    referrerPolicy: { policy: 'no-referrer' },
    crossOriginEmbedderPolicy: true,
    crossOriginOpenerPolicy: { policy: 'same-origin' },
    crossOriginResourcePolicy: { policy: 'same-origin' },
  })
);

// Parsers
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Static files
app.use(express.static(PUBLIC_DIR));

// ---------- UI Routes ----------

app.get('/', (req, res) => {
  res.sendFile(path.join(PUBLIC_DIR, 'login.html'));
});

app.get('/dashboard', (req, res) => {
  res.sendFile(path.join(PUBLIC_DIR, 'dashboard.html'));
});

// ---------- API Routes ----------

// Health
app.get('/api/v1/health', async (req, res) => {
  let captureFiles = [];

  try {
    captureFiles = await listCaptureFiles();
  } catch (err) {
    // keep endpoint resilient
  }

  return jsonSuccess(res, 'sPIffer API is running', {
    httpsCertificatePresent: fs.existsSync(path.join(CERT_DIR, 'server.crt')),
    httpsKeyPresent: fs.existsSync(path.join(CERT_DIR, 'server.key')),
    captureInProgress,
    captureInterface: CAPTURE_INTERFACE,
    captureDirectory: CAPTURE_DIR,
    captureFileCount: captureFiles.length,
    addresses: getServerAddresses(),
  });
});

// Auth
app.post('/api/v1/auth/login', (req, res) => {
  const username = String(req.body.username || '').trim();
  const password = String(req.body.password || '');

  if (!username || !password) {
    return jsonError(res, 400, 'Missing username or password');
  }

  pam.authenticate(
    username,
    password,
    (err) => {
      if (err) {
        console.warn('PAM authentication failed', {
          username,
          message: err.message,
          code: err.code,
        });

        return jsonError(res, 401, 'Authentication failed');
      }

      const payload = { username };
      const token = jwt.sign(payload, SECRET_KEY, {
        expiresIn: JWT_EXPIRES_IN,
      });

      return jsonSuccess(res, 'Login successful', { token });
    },
    {
      serviceName: 'spiffer-web',
    }
  );
});

app.post('/api/v1/auth/logout', verifyToken, (req, res) => {
  return jsonSuccess(res, 'Logout successful');
});

// Capture status
app.get('/api/v1/captures/status', verifyToken, (req, res) => {
  return jsonSuccess(res, 'Capture status retrieved', {
    captureInProgress,
    interface: CAPTURE_INTERFACE,
  });
});

// List captures
app.get('/api/v1/captures', verifyToken, async (req, res, next) => {
  try {
    const files = await listCaptureFiles();
    return jsonSuccess(res, 'Capture files listed', { files });
  } catch (err) {
    return next(err);
  }
});

// Launch capture
app.post('/api/v1/captures', verifyToken, async (req, res, next) => {
  if (captureInProgress) {
    return jsonError(
      res,
      409,
      'Another capture is already in progress'
    );
  }

  const { filename, format, time_delay, unit_delay } = req.body;

  if (!filename || !isValidCaptureName(filename)) {
    return jsonError(res, 400, 'Invalid filename');
  }

  if (!isValidCaptureFormat(format)) {
    return jsonError(res, 400, 'Invalid format');
  }

  if (!isValidDelayUnit(unit_delay)) {
    return jsonError(res, 400, 'Invalid delay unit');
  }

  const numericDelay = Number(time_delay);
  if (!Number.isFinite(numericDelay) || numericDelay <= 0) {
    return jsonError(res, 400, 'Invalid delay');
  }

  const durationInSeconds =
    unit_delay === 'minutes' ? numericDelay * 60 : numericDelay;

  const outputFile = buildCaptureFilePath(filename, format);
  const finalFilename = path.basename(outputFile);

  captureInProgress = true;

  try {
    const result = await runTsharkCapture({
      outputFile,
      durationInSeconds,
    });

    if (result.stderr) {
      console.warn('tshark warning:', result.stderr);
    }

    return jsonSuccess(res, 'Capture completed successfully', {
      filename: finalFilename,
      path: outputFile,
      durationInSeconds,
      interface: CAPTURE_INTERFACE,
    });
  } catch (err) {
    console.error('Capture error:', err);
    if (err.stderr) {
      console.error('tshark stderr:', err.stderr);
    }
    return next(err);
  } finally {
    captureInProgress = false;
  }
});

// Download capture
app.get('/api/v1/captures/:filename/download', verifyToken, async (req, res) => {
  const filename = req.params.filename;

  if (!/^[a-zA-Z0-9_.-]+$/.test(filename)) {
    return jsonError(res, 400, 'Invalid filename');
  }

  const filePath = path.join(CAPTURE_DIR, path.basename(filename));

  try {
    await fsp.access(filePath, fs.constants.R_OK);
  } catch {
    return jsonError(res, 404, 'File not found');
  }

  return res.download(filePath, filename, (err) => {
    if (err && !res.headersSent) {
      console.error('Download error:', err);
      return jsonError(res, 500, 'Failed to download file');
    }
  });
});

// Delete capture
app.delete('/api/v1/captures/:filename', verifyToken, async (req, res) => {
  const filename = req.params.filename;

  if (!/^[a-zA-Z0-9_.-]+$/.test(filename)) {
    return jsonError(res, 400, 'Invalid filename');
  }

  const filePath = path.join(CAPTURE_DIR, path.basename(filename));

  try {
    await fsp.unlink(filePath);
    return jsonSuccess(res, 'Capture deleted', { filename });
  } catch (err) {
    if (err.code === 'ENOENT') {
      return jsonError(res, 404, 'File not found');
    }
    console.error('Delete error:', err);
    return jsonError(res, 500, 'Failed to delete file');
  }
});

// ---------- 404 Handlers ----------

app.use('/api', (req, res) => {
  return jsonError(res, 404, 'API route not found');
});

app.use((req, res) => {
  res.status(404).send('Not Found');
});

// ---------- Error Handler ----------

app.use((err, req, res, next) => {
  console.error('Unhandled application error:', err.stack || err);

  if (isApiRequest(req)) {
    return jsonError(res, 500, 'Internal server error');
  }

  return res.status(500).send('Internal Server Error');
});

// ---------- Servers ----------

const httpServer = http.createServer((req, res) => {
  const host = buildHttpsRedirectHost(req.headers.host);
  res.writeHead(301, { Location: `https://${host}${req.url}` });
  res.end();
});

const httpsServer = https.createServer(httpsOptions, app);

httpServer.on('error', (err) => {
  console.error('HTTP server error:', err);
});

httpsServer.on('error', (err) => {
  console.error('HTTPS server error:', err);
});

httpServer.listen(PORT_HTTP, '0.0.0.0', () => {
  console.log(`HTTP redirect server listening on 0.0.0.0:${PORT_HTTP}`);
});

httpsServer.listen(PORT_HTTPS, '0.0.0.0', () => {
  console.log(`HTTPS server listening on 0.0.0.0:${PORT_HTTPS}`);

  const addresses = getServerAddresses();
  if (addresses.length > 0) {
    console.log('Available IPv4 addresses:');
    for (const entry of addresses) {
      console.log(` - ${entry.interface}: https://${entry.address}:${PORT_HTTPS}`);
    }
  } else {
    console.log('No non-loopback IPv4 address currently available.');
  }
});