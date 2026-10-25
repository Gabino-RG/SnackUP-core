bool isProductAvailable(Map<String, dynamic> product) {
  final stock = product['stock'];
  return product['isAvailable'] == true && stock is num && stock > 0;
}
