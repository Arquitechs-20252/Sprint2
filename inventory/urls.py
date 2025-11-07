from django.urls import path
from . import views

app_name = "inventory"

urlpatterns = [
    path("", views.home, name="home"),  # Página principal
    path("health/", views.health_check, name="health_check"),  # Health check
    path("products/", views.product_list, name="product_list"),  # Listado de productos / búsqueda GET
    path("product/<str:barcode>/", views.get_location, name="get_location"),  # Detalle de producto por barcode
    path("product/<str:barcode>/out/", views.inventory_out, name="inventory_out"),  # Descontar stock
    path("product/create/", views.product_create, name="product_create"),  # Crear producto vía POST
]
