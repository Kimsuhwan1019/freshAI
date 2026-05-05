class Ingredient {
  final String id;
  final String userId;
  final String name;
  final double? quantity;
  final String? unit;
  final String? category;
  final DateTime? expiryDate;
  final DateTime createdAt;

  const Ingredient({
    required this.id,
    required this.userId,
    required this.name,
    this.quantity,
    this.unit,
    this.category,
    this.expiryDate,
    required this.createdAt,
  });

  factory Ingredient.fromJson(Map<String, dynamic> json) {
    return Ingredient(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      quantity: json['quantity'] != null
          ? (json['quantity'] as num).toDouble()
          : null,
      unit: json['unit'] as String?,
      category: json['category'] as String?,
      expiryDate: json['expiry_date'] != null
          ? DateTime.parse(json['expiry_date'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'name': name,
      if (quantity != null) 'quantity': quantity,
      if (unit != null) 'unit': unit,
      if (category != null) 'category': category,
      if (expiryDate != null)
        'expiry_date': expiryDate!.toIso8601String().split('T')[0],
    };
  }
}
