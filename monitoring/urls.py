from django.contrib import admin
from django.urls import path
from inventory import views

urlpatterns = [
    path('', views.home),
    path('admin/', admin.site.urls),
    path('product/', views.product_list),
    path('product/<str:barcode>/', views.get_location),
    path('product/<str:barcode>/out/', views.inventory_out),
    path('health-check/', views.health_check),
]

