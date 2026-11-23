/// Error de negocio con un mensaje listo para mostrar al usuario.
class AeroException implements Exception {
  const AeroException(this.message);
  final String message;

  @override
  String toString() => message;
}
