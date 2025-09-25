from django.urls import path
from . import views

urlpatterns = [
    path('health-check/', views.health_check),
    path('product/<str:barcode>/', views.get_product),
    path('product/<str:barcode>/out/', views.product_out),
    path('product/', views.create_or_update_product),
]
