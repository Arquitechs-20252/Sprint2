from django.db import models

class InventoryProduct(models.Model):
    id = models.BigAutoField(primary_key=True)
    name = models.CharField(max_length=200)  
    barcode = models.CharField(unique=True, max_length=64)
    location = models.CharField(max_length=255)
    quantity = models.IntegerField()
    last_updated = models.DateTimeField(auto_now=True) 

    class Meta:
        db_table = 'inventory_product' 

