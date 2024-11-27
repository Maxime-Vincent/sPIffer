const express = require('express');
const bodyParser = require('body-parser');
const pam = require('authenticate-pam');
const jwt = require('jsonwebtoken');
const helmet = require('helmet');
const { exec } = require('child_process');
const fs = require('fs');
const http = require('http');
const https = require('https');
const path = require('path');
const os = require('os');
const crypto = require('crypto'); // To generate a random secret key
const app = express();
const PORT_HTTP = 3000;      // HTTP Port
const PORT_HTTPS = 443;      // HTTPS Port
const IP = getIpAddress('eth0');
const UPLOAD_FOLDER = "/home/sPIffer/tshark_capture/";

// Path for key and certificate auto-signed
const httpsOptions = {
   key: fs.readFileSync(path.join(__dirname, '/certificate/server.key')),
   cert: fs.readFileSync(path.join(__dirname, '/certificate/server.crt'))
};

// Variable to check if capture is in progress
let captureInProgress = false;

// Create the capture folder if it doesn't exist
if (!fs.existsSync(UPLOAD_FOLDER)) {
   fs.mkdirSync(UPLOAD_FOLDER);
}

// Function to get the IP address of the specified interface
function getIpAddress(interfaceName) {
   const interfaces = os.networkInterfaces();
   if (interfaces[interfaceName]) {
       const addresses = interfaces[interfaceName];
       for (const address of addresses) {
           // Check if it's an IPv4 address and not a loopback address
           if (address.family === 'IPv4' && !address.internal) {
               console.log(`IP address of eth0 is: ${address.address}`);
               return address.address;
           }
       }
   }
   process.exit(1); // Exit if the interface is not found
}

// Function to generate a random secret key on server startup
function generateSecretKey() {
   return crypto.randomBytes(64).toString('hex'); // Generate a 64-byte key
}

// Generate the secret key at server startup
const SECRET_KEY = generateSecretKey();

// Middleware to verify JWT token
function verifyToken(req, res, next) {
   const token = req.headers['authorization'] && req.headers['authorization'].split(' ')[1];
   if (!token) {
       return res.status(403).json({ error: "Missing token" });
   }
   jwt.verify(token, SECRET_KEY, (err, decoded) => {
       if (err) {
           return res.status(401).json({ error: "Invalid or expired token" });
       }
       req.user = decoded; // Add decoded user info to request for use in routes
       next();
   });
}

// Middleware to redirect HTTP to HTTPS
app.use((req, res, next) => {
   if (!req.secure) {
       return res.redirect(`https://${req.headers.host}${req.url}`);
   }
   next();
});

// Secure HTTP headers with Helmet
app.use(helmet({
   contentSecurityPolicy: {
       directives: {
           defaultSrc: ["'self'"],
           scriptSrc: ["'self'"],
           styleSrc: ["'self'", "'unsafe-inline'"],
           imgSrc: ["'self'", "data:"],
           connectSrc: ["'self'"],
           frameAncestors: ["'none'"]
       }
   },
   referrerPolicy: { policy: "no-referrer" },
   crossOriginEmbedderPolicy: true,
   crossOriginOpenerPolicy: { policy: "same-origin" },
   crossOriginResourcePolicy: { policy: "same-origin" }
}));

app.use((req, res, next) => {
   res.setHeader('X-Frame-Options', 'DENY');
   res.setHeader('X-Content-Type-Options', 'nosniff');
   res.setHeader('Content-Security-Policy', "default-src 'self'");
   res.setHeader('Referrer-Policy', 'no-referrer');
   res.setHeader('Permissions-Policy', 'geolocation=(), microphone=()');
   next();
});

// Middleware to parse JSON and URL-encoded data
app.use(express.json());
app.use(bodyParser.urlencoded({ extended: true }));

// Serve static files (HTML, CSS, etc.)
app.use(express.static(path.join(__dirname, 'public')));

// Login page route
app.get('/', (req, res) => {
   res.sendFile(path.join(__dirname, 'public', 'login.html'));
});

// Login handling route
app.post('/login', (req, res) => {
   const { username, password } = req.body;
   pam.authenticate(username, password, (err) => {
       if (err) {
           console.log('Authentication failed:', err);
           return res.status(401).json({ error: err });
       }
       console.log('Authentication successful');
       // Create the JWT payload
       const payload = { username: username };
       // Generate JWT token with 10 minutes expiration
       const token = jwt.sign(payload, SECRET_KEY, { expiresIn: '10m' });
       res.status(200).json({
           message: 'Login successful',
           token: token
       });
   });
});

// Processing of logout
app.post('/logout', verifyToken, (req, res) => {
    if (req.session) {
        req.session.destroy(err => {
            if (err) {
                console.error('Erreur lors de la destruction de la session:', err);
                return res.status(500).send('Erreur de serveur');
            }
            // Redirection to login page
            res.clearCookie('connect.sid'); // Delete cookie of session
            currentSessionId = null;
            console.log("Logout successful");
            return res.redirect('/'); // Redirection from server side
        });
    } else {
        return res.redirect('/'); // Redirect even if sesson still active
    }
});

// Dashboard page (protected by JWT)
app.get('/dashboard', (req, res) => {
   res.sendFile(path.join(__dirname, 'public', 'dashboard.html'));
});

app.post('/browsefiles', verifyToken, (req, res) => {
    const command = `ls /home/sPIffer/tshark_capture`;
    exec(command, (error, stdout, stderr) => {
        if (error) {
            console.error(`Error executing command: ${error}`);
            res.status(500).json({ Error: error.message });
            return;
        }
        if (stderr) {
            console.warn(`Warning: ${stderr}`);
        }
        const files = stdout.split("\n").filter((file) => file.length > 0);

        res.json({
            Info: `Command well processed`,
            Files: JSON.stringify(files),
        });
    });
});

// File download route
app.post('/download_capture', verifyToken, (req, res) => {
   const { filecap } = req.body;
   if (!filecap) {
       return res.status(400).send("Filename not defined");
   }
   const filePath = path.join(UPLOAD_FOLDER, filecap);
   // Check if file exists
   if (fs.existsSync(filePath)) {
       res.setHeader("Content-Disposition", `attachment; filename="${filecap}"`);
       res.setHeader("Content-Type", "application/octet-stream");
       const fileStream = fs.createReadStream(filePath);
       fileStream.pipe(res);
       fileStream.on("error", (err) => {
           console.error("Error for reading the file:", err);
           res.status(500).send("Internal Server Error.");
       });
   } else {
       res.status(404).send("File not found.");
   }
});

// Launch network capture
app.post('/launch_capture', verifyToken, (req, res) => {
   if (captureInProgress) {
       return res.status(503).json({
           Error: "Another capture is still in progress. Please wait for the previous capture to finish."
       });
   } else {
       const { filename, format, time_delay, unit_delay } = req.body;
       // Validate parameters
       const filenameRegex = /^[a-zA-Z0-9_\-]+$/;
       const validUnits = ['seconds', 'minutes'];
       const validFormats = ['pcapng', 'pcap'];
       if (!filename || !filenameRegex.test(filename)) {
           return res.status(400).json({ Error: "Invalid filename" });
       }
       if (isNaN(time_delay) || time_delay <= 0) {
           return res.status(400).json({ Error: "Invalid delay" });
       }
       if (!validUnits.includes(unit_delay)) {
           return res.status(400).json({ Error: "Invalid delay unit" });
       }
       if (!validFormats.includes(format)) {
           return res.status(400).json({ Error: "Invalid format" });
       }
       const durationInSeconds = unit_delay === 'minutes' ? time_delay * 60 : time_delay;
       const safeFilename = path.basename(filename);
       const command = `sudo tshark -i br0 -a duration:${durationInSeconds} -w ${UPLOAD_FOLDER}${safeFilename}.${format}`;
       captureInProgress = true;
       exec(command, (error, stdout, stderr) => {
           if (error) {
               console.error(`Error executing command: ${error}`);
               res.status(500).json({ Error: error.message });
               return;
           }
           captureInProgress = false;
           res.status(200).json({ Info: 'Capture completed successfully' });
       });
   }
});

// Catch-all error handling for undefined routes
app.use((err, req, res, next) => {
   console.error(err.stack);
   res.status(500).send('Internal Server Error');
});

// HTTP server for redirection to HTTPS
http.createServer((req, res) => {
   res.writeHead(301, { "Location": `https://${req.headers.host}${req.url}` });
   res.end();
}).listen(PORT_HTTP, () => {
   console.log(`HTTP Server for redirection at http://${IP}:${PORT_HTTP}`);
});

// HTTPS server
https.createServer(httpsOptions, app).listen(PORT_HTTPS, () => {
   console.log(`HTTPS Server running at https://${IP}:${PORT_HTTPS}`);
});