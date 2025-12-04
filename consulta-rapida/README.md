# Consulta Rápida Service - Microservicio con Cache-Aside Pattern

API de consulta rápida de productos con Redis Cache y PostgreSQL.

## Arquitectura

- **Cache:** Redis (ElastiCache)
- **Base de datos:** PostgreSQL
- **Patrón:** Cache-Aside
- **Deployment:** AWS App Runner

## Endpoints

- `GET /health` - Health check
- `GET /productos/populares` - Top 20 productos con más stock
- `GET /productos/categoria/:categoria` - Productos por categoría
- `GET /stats` - Estadísticas de caché y base de datos
- `DELETE /cache` - Limpiar caché

## Variables de Entorno
```
PORT=8080
REDIS_HOST=your-redis-endpoint
REDIS_PORT=6379
DB_HOST=172.31.16.20
DB_NAME=inventario_db
DB_USER=apprunner_user
DB_PASSWORD=your-password
DB_PORT=5432
```

## Latencia Objetivo

- Cache HIT: < 15ms
- Cache MISS: < 200ms