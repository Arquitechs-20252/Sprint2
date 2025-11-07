from django.urls import path
from . import views

urlpatterns = [
    path('', views.home, name='home'),
    path('health/', views.health_check, name='health_check'),
    path('products/', views.product_list, name='product_list'),  # GET
    path('product/<str:barcode>/', views.get_location, name='product_detail'),  # GET detalle
    path('product/out/<str:barcode>/', views.inventory_out, name='inventory_out'),  # GET o POST si quieres
    path('product/', views.product_create, name='product_create'),  # POST
]
