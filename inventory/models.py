from django.db import models

class Product(models.Model):
    barcode = models.CharField(max_length=64, unique=True)
    location = models.CharField(max_length=255)
    quantity = models.IntegerField(default=0)
    last_updated = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.barcode} @ {self.location} (q={self.quantity})"
