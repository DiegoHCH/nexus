/// La franja del día, para saludar como saluda una persona.
///
/// Vive en `core` y no en la feature porque **de esto habla el texto**: los dos
/// idiomas la reparten igual y quien la calcula es el dominio. Al revés —la
/// franja dentro de `assistant`— obligaría a que `core/i18n` importara una
/// feature, que es la dependencia justo del revés.
///
/// Las doce y las ocho, que es como se saluda en español y no como reparte el
/// reloj: nadie da «buenos días» a las dos de la tarde ni «buenas tardes» a las
/// once de la noche. Y antes de las seis sigue siendo de noche — quien arranca a
/// esa hora no está empezando el día, lo está acabando.
enum FranjaDelDia { manana, tarde, noche }
