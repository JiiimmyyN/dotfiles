const WebSocket = require('ws');

const ws = new WebSocket('ws://127.0.0.1:6005');

let buffer = Buffer.alloc(0);
let contentLength = -1;

ws.on('open', () => {
    process.stdin.on('data', (chunk) => {
        buffer = Buffer.concat([buffer, chunk]);

        while (true) {
            if (contentLength === -1) {
                // We are looking for the header
                const headerSeparator = buffer.indexOf('\r\n\r\n');
                if (headerSeparator === -1) {
                    break; // Need more data
                }

                // Parse header
                const headerPart = buffer.slice(0, headerSeparator).toString();
                const match = headerPart.match(/Content-Length: (\d+)/i);
                if (match) {
                    contentLength = parseInt(match[1], 10);
                }
                
                // Move buffer past the header
                buffer = buffer.slice(headerSeparator + 4);
            }

            if (contentLength !== -1) {
                // We are waiting for the body
                if (buffer.length >= contentLength) {
                    const messageBody = buffer.slice(0, contentLength).toString('utf8');
                    
                    try {
                        ws.send(messageBody);
                    } catch (e) {
                        console.error('Error sending to Godot:', e);
                    }

                    // Remove processed message from buffer
                    buffer = buffer.slice(contentLength);
                    contentLength = -1; // Reset for next message
                } else {
                    break; // Need more data
                }
            }
        }
    });
});

ws.on('message', (data) => {
    // data from Godot is a raw buffer or string of JSON
    const msg = data.toString();
    const length = Buffer.byteLength(msg, 'utf8');
    
    // Send back to OpenCode with LSP headers
    process.stdout.write(`Content-Length: ${length}\r\n\r\n${msg}`);
});

ws.on('error', (err) => {
    // console.error('WebSocket error:', err);
    process.exit(1);
});

ws.on('close', () => {
    process.exit(0);
});
