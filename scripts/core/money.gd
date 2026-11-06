class_name Money
## Moneda del jugador (por la región de su idioma: es_MX -> MXN) y precios con su
## símbolo. Los precios de los paquetes de gemas vienen de roa_gem_prices; si no hay
## precio en su moneda, se muestra y se cobra en USD (igual que en el servidor).

const FALLBACK := "USD"

const EURO := ["AT", "BE", "CY", "DE", "EE", "ES", "FI", "FR", "GR", "HR", "IE", "IT", "LT", "LU", "LV", "MT", "NL",
	"PT", "SI", "SK"]
const BY_COUNTRY := {
	"US": "USD", "MX": "MXN", "CA": "CAD", "GB": "GBP", "BR": "BRL", "CO": "COP", "CL": "CLP", "PE": "PEN",
	"AR": "ARS", "UY": "UYU", "GT": "GTQ", "CR": "CRC", "DO": "DOP", "BO": "BOB", "PY": "PYG", "HN": "HNL",
	"NI": "NIO", "AU": "AUD", "NZ": "NZD", "JP": "JPY", "IN": "INR", "CH": "CHF",
}
const SYMBOLS := {"EUR": "€", "GBP": "£", "BRL": "R$", "PEN": "S/", "JPY": "¥", "INR": "₹"}
const NO_DECIMALS := ["CLP", "COP", "JPY", "PYG", "CRC"]


## "MXN", "EUR"… según el país del idioma del equipo o del navegador.
static func local_currency() -> String:
	var locale := OS.get_locale().replace("-", "_")   # "es_MX", "en_US", "es"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--moneda="):
			return a.get_slice("=", 1).to_upper()
	var parts := locale.split("_")
	var country := parts[1].to_upper() if parts.size() > 1 else ""
	if country in EURO:
		return "EUR"
	return BY_COUNTRY.get(country, FALLBACK)


## La moneda en la que se le muestra y cobra: la suya si tiene precio, si no USD.
static func pick(prices: Dictionary) -> String:
	var cur := local_currency()
	return cur if prices.has(cur) else FALLBACK


## "$99.00 MXN", "€4.99", "R$24.90", "$19,900 COP".
static func format(amount: float, currency: String) -> String:
	var digits := 0 if currency in NO_DECIMALS else 2
	var whole := int(floor(amount))
	var text := thousands(whole)
	if digits > 0:
		text += ".%02d" % roundi((amount - whole) * 100.0)
	if SYMBOLS.has(currency):
		return SYMBOLS[currency] + text
	if currency == "USD":
		return "$" + text + " USD"
	return "$%s %s" % [text, currency]


static func thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
