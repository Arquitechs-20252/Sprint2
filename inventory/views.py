from django.shortcuts import render, get_object_or_404
from django.views.decorators.csrf import csrf_exempt
from django.http import JsonResponse
import json
from .models import InventoryProduct

def home(request):
    return render(request, "home.html")

def health_check(request):
    return render(request, "inventory/health_check.html")

def product_list(request):
    query = request.GET.get("q") 
    productos = InventoryProduct.objects.all()
    if query:
        productos = productos.filter(barcode__icontains=query)
    return render(request, "inventory/product_list.html", {"productos": productos, "query": query})

def get_location(request, barcode):
    producto = get_object_or_404(InventoryProduct, barcode=barcode)
    return render(request, "inventory/product_detail.html", {"producto": producto})

def inventory_out(request, barcode):
    producto = get_object_or_404(InventoryProduct, barcode=barcode)
    mensaje = ""
    if producto.quantity > 0:
        producto.quantity -= 1
        producto.save()
        mensaje = f"Se descontó 1 unidad de {producto.name}. Nueva cantidad: {producto.quantity}"
    else:
        mensaje = f"{producto.name} no tiene stock disponible."
    return render(request, "inventory/inventory_out.html", {"mensaje": mensaje})

# Crear producto vía POST
@csrf_exempt
def product_create(request):
    if request.method == "POST":
        try:
            data = json.loads(request.body)
            producto = InventoryProduct.objects.create(
                name=data["name"],
                barcode=data["barcode"],
                location=data["location"],
                quantity=data["quantity"]
            )
            return JsonResponse({
                "id": producto.id,
                "name": producto.name,
                "barcode": producto.barcode,
                "location": producto.location,
                "quantity": producto.quantity
            })
        except (KeyError, json.JSONDecodeError) as e:
            return JsonResponse({"error": str(e)}, status=400)
    return JsonResponse({"error": "Method not allowed"}, status=405)
