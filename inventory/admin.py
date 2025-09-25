from django.contrib import admin
from .models import Product

@admin.register(Product)
class ProductAdmin(admin.ModelAdmin):
    list_display = ('barcode','location','quantity','last_updated')
    search_fields = ('barcode','location')
