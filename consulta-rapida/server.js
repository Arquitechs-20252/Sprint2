const express = require('express');
const redis = require('redis');
const { Pool } = require('pg');
const cors = require('cors');

const app = express();
app.use(express.json());
app.use(cors());

// ============================================
// CONFIGURACIÓN
// ============================================

// Cliente Redis
const redisClient = redis.createClient({
  socket: {
    host: process.env.REDIS_HOST || 'localhost',
    port: parseInt(process.env.REDIS_PORT || '6379'),
    tls: true // Porque habilitamos cifrado en tránsito
  }
});

redisClient.on('error', (err) => {
  console.error('Redis Client Error:', err);
});

redisClient.connect().then(() => {
  console.log('✓ Conectado a Redis');
}).catch(err => {
  console.error('✗ Error conectando a Redis:', err);
});

// Pool PostgreSQL
const pgPool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  database: process.env.DB_NAME || 'inventario_db',
  user: process.env.DB_USER || 'apprunner_user',
  password: process.env.DB_PASSWORD,
  port: parseInt(process.env.DB_PORT || '5432'),
  max: 10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

pgPool.query('SELECT NOW()', (err, res) => {
  if (err) {
    console.error('✗ Error conectando a PostgreSQL:', err);
  } else {
    console.log('✓ Conectado a PostgreSQL');
  }
});

// ============================================
// ENDPOINTS
// ============================================

// Health Check
app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy',
    service: 'consulta-rapida',
    timestamp: new Date().toISOString(),
    redis: redisClient.isOpen ? 'connected' : 'disconnected'
  });
});

// Productos populares (Cache-Aside Pattern)
app.get('/productos/populares', async (req, res) => {
  const startTime = Date.now();
  const cacheKey = 'productos:populares';
  
  try {
    // Paso 1: Buscar en caché
    const cachedData = await redisClient.get(cacheKey);
    
    if (cachedData) {
      const latency = Date.now() - startTime;
      console.log(`✓ Cache HIT - Latencia: ${latency}ms`);
      
      return res.json({
        success: true,
        data: JSON.parse(cachedData),
        source: 'cache',
        latency: `${latency}ms`,
        cached: true
      });
    }
    
    console.log('✗ Cache MISS - Consultando base de datos...');
    
    // Paso 2: Consultar base de datos
    const result = await pgPool.query(
      `SELECT p.id, p.nombre, p.descripcion, p.precio, p.stock, p.categoria,
              i.cantidad_disponible, i.cantidad_reservada
       FROM productos p
       LEFT JOIN inventario i ON p.id = i.producto_id
       WHERE p.stock > 0
       ORDER BY p.stock DESC
       LIMIT 20`
    );
    
    // Paso 3: Guardar en caché (TTL: 5 minutos)
    await redisClient.setEx(cacheKey, 300, JSON.stringify(result.rows));
    
    const latency = Date.now() - startTime;
    console.log(`✓ Datos guardados en caché - Latencia: ${latency}ms`);
    
    res.json({
      success: true,
      data: result.rows,
      source: 'database',
      latency: `${latency}ms`,
      cached: false
    });
    
  } catch (error) {
    console.error('Error en /productos/populares:', error);
    res.status(500).json({ 
      success: false,
      error: error.message 
    });
  }
});

// Productos por categoría
app.get('/productos/categoria/:categoria', async (req, res) => {
  const startTime = Date.now();
  const { categoria } = req.params;
  const cacheKey = `productos:categoria:${categoria.toLowerCase()}`;
  
  try {
    const cachedData = await redisClient.get(cacheKey);
    
    if (cachedData) {
      const latency = Date.now() - startTime;
      return res.json({
        success: true,
        categoria,
        data: JSON.parse(cachedData),
        source: 'cache',
        latency: `${latency}ms`
      });
    }
    
    const result = await pgPool.query(
      `SELECT p.id, p.nombre, p.descripcion, p.precio, p.stock, p.categoria,
              i.cantidad_disponible
       FROM productos p
       LEFT JOIN inventario i ON p.id = i.producto_id
       WHERE LOWER(p.categoria) = LOWER($1) AND p.stock > 0
       ORDER BY p.stock DESC
       LIMIT 50`,
      [categoria]
    );
    
    if (result.rows.length > 0) {
      await redisClient.setEx(cacheKey, 300, JSON.stringify(result.rows));
    }
    
    const latency = Date.now() - startTime;
    res.json({
      success: true,
      categoria,
      data: result.rows,
      source: 'database',
      latency: `${latency}ms`,
      total: result.rows.length
    });
    
  } catch (error) {
    console.error(`Error en /productos/categoria/${categoria}:`, error);
    res.status(500).json({ 
      success: false,
      error: error.message 
    });
  }
});

// Estadísticas
app.get('/stats', async (req, res) => {
  try {
    const keys = await redisClient.keys('productos:*');
    res.json({
      success: true,
      redis: {
        connected: redisClient.isOpen,
        totalKeys: keys.length
      },
      postgres: {
        poolSize: pgPool.totalCount,
        idleConnections: pgPool.idleCount
      }
    });
  } catch (error) {
    res.status(500).json({ 
      success: false,
      error: error.message 
    });
  }
});

// Limpiar caché
app.delete('/cache', async (req, res) => {
  try {
    const keys = await redisClient.keys('productos:*');
    if (keys.length > 0) {
      await redisClient.del(keys);
    }
    res.json({
      success: true,
      message: 'Caché limpiada',
      keysDeleted: keys.length
    });
  } catch (error) {
    res.status(500).json({ 
      success: false,
      error: error.message 
    });
  }
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('SIGTERM recibido, cerrando conexiones...');
  await redisClient.quit();
  await pgPool.end();
  process.exit(0);
});

// Iniciar servidor
const PORT = process.env.PORT || 8080;
app.listen(PORT, '0.0.0.0', () => {
  console.log('==========================================');
  console.log(`🚀 Consulta Rápida Service`);
  console.log(`📡 Puerto: ${PORT}`);
  console.log(`🔗 Redis: ${process.env.REDIS_HOST || 'localhost'}`);
  console.log(`🔗 PostgreSQL: ${process.env.DB_HOST || 'localhost'}`);
  console.log('==========================================');
});
