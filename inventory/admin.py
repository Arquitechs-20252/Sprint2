from django.contrib import admin
from .models import InventoryProduct  # 👈 corregido

@admin.register(InventoryProduct)
class InventoryProductAdmin(admin.ModelAdmin):
    list_display = ('id', 'name', 'barcode', 'location', 'quantity', 'last_updated')
    search_fields = ('name', 'barcode', 'location')
    list_filter = ('location',)

