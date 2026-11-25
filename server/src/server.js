require('dotenv').config();
const http = require('http');
const { Server } = require('socket.io');
const connectDB = require('./config/db');
const app = require('./app');
const initializeSockets = require('./sockets');

const startServer = async () => {
  await connectDB();

  const server = http.createServer(app);
  const io = new Server(server, {
    cors: { origin: process.env.CLIENT_ORIGINS?.split(',') || '*', methods: ['GET', 'POST', 'PUT'] },
  });

  app.set('io', io);
  initializeSockets(io);

  const PORT = process.env.PORT || 5000;
  server.listen(PORT, '0.0.0.0', () => console.log(`SwiftRoute Logistics Server running on port ${PORT}`));
};

startServer();
