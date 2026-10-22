String friendlyProgress(
  String raw, {
  bool converting = false,
  double percent = -1,
}) {
  if (converting) return 'Convirtiendo a MP3…';
  if (percent >= 0) return 'Descargando canción…';
  final value = raw.toLowerCase();
  if (value.contains('actualiz')) return 'Actualizando el motor…';
  if (value.contains('leyendo')) return 'Leyendo canciones…';
  if (value.contains('preparando')) return 'Preparando descarga…';
  if (value.contains('retry') || value.contains('reintent'))
    return 'Reintentando conexión…';
  return 'Buscando el audio…';
}

String friendlyError(Object error) {
  final text = error.toString().toLowerCase();
  if (text.contains('cancel')) return 'Operación cancelada.';
  if (text.contains('429'))
    return 'Demasiadas solicitudes. Inténtalo más tarde.';
  if (text.contains('bot') || text.contains('403'))
    return 'El proveedor no permitió acceder a esta canción.';
  if (text.contains('timeout') ||
      text.contains('socket') ||
      text.contains('network'))
    return 'No se pudo conectar. Revisa tu conexión e inténtalo otra vez.';
  if (text.contains('space') || text.contains('espacio'))
    return 'No hay espacio suficiente para guardar la canción.';
  if (text.contains('private') || text.contains('unavailable'))
    return 'Esta canción no está disponible.';
  return 'No se pudo completar. Puedes ver el detalle del error.';
}
