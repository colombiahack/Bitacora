/// Conversores tolerantes: SQLite devuelve booleanos como 0/1 y JSON como true/false.
bool asBool(Object? v) => v == true || v == 1;

DateTime? asDateOrNull(Object? v) =>
    (v == null || (v is String && v.isEmpty)) ? null : DateTime.parse(v as String);

double? asDoubleOrNull(Object? v) => (v as num?)?.toDouble();

double asDouble(Object? v) => (v as num?)?.toDouble() ?? 0;

int asInt(Object? v) => (v as num?)?.toInt() ?? 0;
