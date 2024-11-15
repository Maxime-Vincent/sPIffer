const express = require('express');
const session = require("express-session");
const bodyParser = require('body-parser');
const pam = require('authenticate-pam');
const helmet = require('helmet');
const { exec } = require('child_process');
const fs = require('fs');
const http = require('http');
const https = require('https');
const path = require('path')
const os = require('os');
const app = express();

const PORT_HTTP = 3000;      // Port HTTP
const PORT_HTTPS = 443;    // Port HTTPS
const IP = getIpAddress('eth0');
const UPLOAD_FOLDER = "/home/sPIffer/tshark_capture/";

// Path for key and certificate auto-signed
const httpsOptions = {
    key: fs.readFileSync(path.join(__dirname, '/certificate/server.key')),
    cert: fs.readFileSync(path.join(__dirname, '/certificate/server.crt'))
};

let currentSessionId = null; // Store the active and only session ID
let captureInProgress = false;

// Create the folder if it does not exists
if (!fs.existsSync(UPLOAD_FOLDER)) {
    fs.mkdirSync(UPLOAD_FOLDER);
}

function getIpAddress(interfaceName) {
    const interfaces = os.networkInterfaces();
    if (interfaces[interfaceName]) {
        const addresses = interfaces[interfaceName];
        for (const address of addresses) {
            // Verify if it's IPv4 address and not a loopback
            if (address.family === 'IPv4' && !address.internal) {
                // Return the IP address
                console.log(`IP address of eth0 is: ${address.address}`)
                return address.address;
            }
        }
    }
    process.exit(1);
}

// Method to check if the user is Authenticated
function isAuthenticated(req, res, next) {
    if (req.session.isAuthenticated) {
        return next(); // User has been connected
    } else {
        res.redirect('/'); // Return to login page
    }
}

app.use(session({
    secret: "aetuoqdgjlwcbzryipsfhkmxvn", // Key
    resave: false,
    saveUninitialized: false,
    cookie: {
        secure: true, // for HTTPS
        httpOnly: true,
        sameSite: 'strict', // Unable request CSRF
        maxAge: 600000 // Session lifetime (10 min)
    }
}));

// Middleware for redirection to HTTPS
app.use((req, res, next) => {
    if (!req.secure) {  // Vérifie si la requête n'est pas en HTTPS
        return res.redirect(`https://${req.headers.host}${req.url}`);
    }
    next();
});

// Configure header CSP to allow scripts
app.use(helmet({
    contentSecurityPolicy: {
        directives: {
            defaultSrc: ["'self'"],
            scriptSrc: ["'self'"],
            styleSrc: ["'self'", "'unsafe-inline'"], // Évitez 'unsafe-inline' si possible
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
    // Protection against clickjacking
    res.setHeader('X-Frame-Options', 'DENY');
    // Prevent the type MIME sniffing
    res.setHeader('X-Content-Type-Options', 'nosniff');
    // Policy for content security
    res.setHeader('Content-Security-Policy', "default-src 'self'");
    // Policy for referrer
    res.setHeader('Referrer-Policy', 'no-referrer');
    // Policy for permissions
    res.setHeader('Permissions-Policy', 'geolocation=(), microphone=()');
    next();
});

// Middleware for data parsing
app.use(express.json());
app.use(bodyParser.urlencoded({ extended: true }));

// Serve static files (HTML, CSS, etc.)
app.use(express.static(path.join(__dirname, 'public')));

// Connection page
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'login.html'));
});

// Processing of login
app.post('/login', (req, res) => {
    const { username, password } = req.body;
    if (currentSessionId) {
        return res.status(403).json({ error: "A session is already active. Only one connection allowed at a time." });
    }
    else {
        // Create new session
        req.session.isAuthenticated = true;
        currentSessionId = req.sessionID; // Set as active session
        pam.authenticate(username, password, (err) => {
            if (err) {
                console.log('Authentication failed:', err);
                res.status(401).json({ error: err });
            } else {
                console.log('Authentication successful');
                req.session.isAuthenticated = true;
                currentSessionId = req.sessionID;
                res.redirect('/dashboard');
            }
        });
    }
});

// Processing of logout
app.post('/logout', (req, res) => {
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

// Dashboard Page
app.get('/dashboard', isAuthenticated, (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'dashboard.html'));
});

app.post('/browsefiles', (req, res) => {
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

app.post('/download_capture', (req, res) => {
    const { filecap } = req.body;
    console.log(filecap);
    if (!filecap) {
        return res.status(400).send("Filename not defined");
    }

    const filePath = path.join(UPLOAD_FOLDER, filecap);
    console.log(filePath);

    // Check if the file exists
    if (fs.existsSync(filePath)) {
        res.setHeader("Content-Disposition", `attachment; filename="${filecap}"`);
        res.setHeader("Content-Type", "application/octet-stream");
        const command = `sudo chmod 666 ${filePath}`;
        exec(command, (error, stdout, stderr) => {
            if (error) {
                console.error(`Error executing command: ${error}`);
                res.status(500).send("Internal Server Error.");
                return;
            }
            if (stderr) {
                console.warn(`Warning: ${stderr}`);
            }
            console.log("File is ready for transfer");
        });
        // Send the file
        const filePath = path.join(UPLOAD_FOLDER, filecap);
        if (fs.existsSync(filePath)) {
            res.download(filePath, (err) => {
                if (err) {
                    console.error('Erreur de téléchargement:', err);
                }
            });
        } else {
            res.status(404).send("File not found.");
        }
    } else {
        res.status(404).send("File not found.");
    }
});

// Launch Network Capture
app.post('/launch_capture', isAuthenticated, (req, res) => {
    if (captureInProgress) {
        return res.status(503).json({
            Error: "Another capture is still in progress. Please wait for previous capture to finish."
        });
    }
    else {
        const { filename, format, time_delay, unit_delay } = req.body;
        // Define validation rules
        const filenameRegex = /^[a-zA-Z0-9_\-]+$/; // Only allow letters, numbers, hyphens, and underscores in filename
        const maxFilenameLength = 40; // Set maximum length for filename to 30 characters
        const validUnits = ['seconds', 'minutes']; // Valid values for unit_delay
        const validFormats = ['pcapng', 'pcap']; // Valid values for unit_delay
        // Validate filename: must be provided, follow safe characters, and respect length limit
        if (!filename || !filenameRegex.test(filename) || filename.length > maxFilenameLength) {
            return res.status(400).json({
                Error: "Invalid filename. Use only letters, numbers, hyphens, and underscores, and no more than 40 characters long."
            });
        }
        // Validate time_delay: must be a positive integer
        if (!time_delay || isNaN(time_delay) || time_delay <= 0) {
            return res.status(400).json({
                Error: "Invalid delay. Please enter a positive number."
            });
        }
        // Validate unit_delay: must be either 'seconds' or 'minutes'
        if (!validUnits.includes(unit_delay)) {
            return res.status(400).json({
                Error: "Invalid unit for delay. Only 'seconds' or 'minutes' are allowed."
            });
        }
        // Validate format: must be either 'pcapng' or 'pcap'
        if (!validFormats.includes(format)) {
            return res.status(400).json({
                Error: "Invalid file format."
            });
        }
        // Convert time_delay to seconds if unit_delay is in minutes
        const durationInSeconds = unit_delay === 'minutes' ? time_delay * 60 : time_delay;
        // Command to run tshark capture with specified filename and duration in seconds
        const safeFilename = path.basename(filename);
        const command = `sudo tshark -i br0 -a duration:${durationInSeconds} -w ${UPLOAD_FOLDER}${safeFilename}.${format}`;
        console.log(req.body);
        console.log("Executing command...");
        captureInProgress = true;
        exec(command, (error, stdout, stderr) => {
            if (error) {
                console.error(`Error executing command: ${error}`);
                res.status(500).json({ Error: error.message });
                return;
            }
            if (stderr) {
                console.warn(`Warning: ${stderr}`);
            }
            console.log("Execution finished.");
            captureInProgress = false;
            res.json({ Info: 'Capture completed successfully' });
        });
    }
});

// For undefined routes path
app.use((err, req, res, next) => {
    console.error(err.stack);
    res.status(500).send('Internal Server Error');
});

// Launcher for HTTP server for redirection only
http.createServer((req, res) => {
    res.writeHead(301, { "Location": `https://${req.headers.host}${req.url}` });
    res.end();
}).listen(PORT_HTTP, () => {
    console.log(`HTTP Server for redirection at http://${IP}:${PORT_HTTP}`);
});
// Launcher for HTTPS server
https.createServer(httpsOptions, app).listen(PORT_HTTPS, () => {
    console.log(`HTTPS Server ready at https://${IP}:${PORT_HTTPS}`);
});