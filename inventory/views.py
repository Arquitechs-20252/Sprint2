from django.shortcuts import render
from django.http import JsonResponse, HttpResponse
from django.views.decorators.csrf import csrf_exempt
from .models import Product
import json
from django.shortcuts import get_object_or_404
from django.utils import timezone

def health_check(request):
    return HttpResponse("OK")

def get_product(request, barcode):
    try:
        p = Product.objects.get(barcode=barcode)
        return JsonResponse({'barcode': p.barcode, 'location': p.location, 'quantity': p.quantity})
    except Product.DoesNotExist:
        return JsonResponse({'message':'not found'}, status=404)

@csrf_exempt
def create_or_update_product(request):
    if request.method != 'POST':
        return JsonResponse({'error':'only POST'}, status=405)
    body = json.loads(request.body.decode('utf-8'))
    barcode = body.get('barcode')
    if not barcode:
        return JsonResponse({'error':'barcode required'}, status=400)
    p, _ = Product.objects.update_or_create(
        barcode=barcode,
        defaults={'location': body.get('location',''), 'quantity': body.get('quantity',0), 'last_updated': timezone.now()}
    )
    return JsonResponse({'barcode':p.barcode,'location':p.location,'quantity':p.quantity}, status=201)

@csrf_exempt
def product_out(request, barcode):
    if request.method != 'POST':
        return JsonResponse({'error':'only POST'}, status=405)
    payload = json.loads(request.body.decode('utf-8') or '{}')
    amount = int(payload.get('amount',1))
    p = get_object_or_404(Product, barcode=barcode)
    if p.quantity < amount:
        return JsonResponse({'error':'insufficient'}, status=400)
    p.quantity -= amount
    p.save()
    return JsonResponse({'barcode':p.barcode,'quantity':p.quantity})
