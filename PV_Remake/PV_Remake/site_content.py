"""Editable public-site content for PVFinder.

Only presentation fields are configurable. No HTML, JavaScript, backend
settings, payment destination, credentials or executable CSS are accepted.
"""
import json
import re
from urllib.parse import urlparse

TEXT = {
    "brand_name": ("PVFINDER", 42),
    "site_announcement": ("", 180),
    "home_access_tag": ("ACCESO CONTROLADO", 55),
    "home_title_first": ("Tu radar.", 85),
    "home_title_second": ("Tu servidor.", 85),
    "home_description": ("Visualiza el historial de huevos de todas las rarezas enviados por recolectores autorizados.", 320),
    "home_side_tag": ("LIVE DETECTION NETWORK", 65),
    "home_side_first": ("Detecta.", 70),
    "home_side_second": ("Clasifica.", 70),
    "home_side_third": ("Monitorea.", 70),
    "home_side_description": ("No se muestran datos ficticios. El feed comienza cuando un recolector autorizado envía una detección.", 320),
    "home_side_status": ("Transmisiones protegidas por permisos", 100),
    "home_access_button": ("ACCEDER AL LIVE FEED", 65),
    "home_live_tag": ("MONITOREO EN TIEMPO REAL", 90),
    "home_live_caption": ("Solo huevos detectados por escáneres en los últimos 90 segundos. Historial interno conservado.", 240),
    "home_footer_text": ("PVFINDER v1.1 · JOIN", 90),
    "sales_page_tag": ("PÁGINA OFICIAL DE VENTAS", 85),
    "sales_eyebrow": ("Accesos · Precios oficiales en USD", 110),
    "sales_title_first": ("Elige tu acceso a", 100),
    "sales_title_second": ("PVFinder.", 100),
    "sales_intro": ("Todos los planes y precios de PVFinder están aquí. Elige tu acceso y paga de forma externa con PayPal. Después abre un ticket privado en Discord para solicitar tu key, que se entrega únicamente tras verificar el pago.", 700),
    "sales_feature_one": ("🌎 Atención internacional", 90),
    "sales_feature_two": ("💵 Precios en USD", 90),
    "sales_feature_three": ("🎟️ Compras por ticket privado", 90),
    "sales_feature_four": ("🔑 Entrega manual de keys", 90),
    "sales_plans_title": ("Planes de acceso", 100),
    "sales_plans_hint": ("Precios de PVFinder en dólares estadounidenses (USD). Todos los planes son pagos únicos, sin renovación automática.", 280),
    "sales_button_label": ("Elegir plan y pagar", 65),
    "sales_featured_tag": ("POPULAR", 38),
    "sales_contact_title": ("¿Ya eres miembro de PVFINDER?", 140),
    "sales_contact_text": ("Abre tu servidor de Discord y crea un ticket en 📦 Order. Si aún no eres miembro, solicita un enlace de invitación al administrador. Los precios solo se publican en esta página.", 450),
    "sales_contact_button": ("Abrir Discord ↗", 65),
    "sales_footer_text": ("Página oficial de precios · Compra por ticket · Entrega manual", 180),
    "sales_extra_title": ("", 140),
    "sales_extra_text": ("", 700),
    "plan_three_name": ("3 días", 60),
    "plan_three_description": ("Tres días de acceso para probar con calma.", 250),
    "plan_weekly_name": ("Semanal", 60),
    "plan_weekly_description": ("Siete días consecutivos de acceso.", 250),
    "plan_biweekly_name": ("2 semanas", 60),
    "plan_biweekly_description": ("Catorce días consecutivos.", 250),
    "plan_monthly_name": ("Mensual", 60),
    "plan_monthly_description": ("Treinta días de acceso sin renovar semanalmente.", 250),
}
PRICES = {"plan_three_price": 7, "plan_weekly_price": 12,
          "plan_biweekly_price": 18, "plan_monthly_price": 25}
COLORS = {"theme_primary": "#a190ff", "theme_secondary": "#66b9ff",
          "theme_background": "#070a11", "theme_sales_background": "#080e20"}
LINKS = {"sales_discord_link": "https://discord.com/channels/1565963083212398804"}
DEFAULTS = {k: value for k, (value, _) in TEXT.items()}
DEFAULTS.update(PRICES)
DEFAULTS.update(COLORS)
DEFAULTS.update(LINKS)

def install(db):
    db.execute("""CREATE TABLE IF NOT EXISTS site_content (
      name TEXT PRIMARY KEY, value_json TEXT NOT NULL,
      updated_at INTEGER NOT NULL, updated_by TEXT NOT NULL
    )""")
    db.execute("""CREATE TABLE IF NOT EXISTS site_edit_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      actor TEXT NOT NULL, changed_keys TEXT NOT NULL, updated_at INTEGER NOT NULL
    )""")

def snapshot(db, lock):
    with lock:
        rows = db.execute("SELECT name,value_json,updated_at FROM site_content").fetchall()
    data = dict(DEFAULTS)
    stamp = 0
    for row in rows:
        if row["name"] not in data:
            continue
        try:
            value = json.loads(row["value_json"])
            data[row["name"]] = validate(row["name"], value)
            stamp = max(stamp, row["updated_at"])
        except (ValueError, TypeError, KeyError, json.JSONDecodeError):
            continue
    return {"ok": True, "values": data, "updated_at": stamp}

def validate(key, value):
    if key in TEXT:
        if not isinstance(value, str):
            raise ValueError("Se requiere texto para " + key)
        max_len = TEXT[key][1]
        if len(value) > max_len or any(ord(c) < 32 and c not in "\n\t" for c in value):
            raise ValueError("Texto inválido o demasiado largo: " + key)
        return value.strip()
    if key in PRICES:
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise ValueError("Precio inválido: " + key)
        if not (1 <= value <= 999.99):
            raise ValueError("Precio permitido: 1 a 999.99 USD")
        cents = round(float(value) * 100)
        if abs(value * 100 - cents) > 0.00001:
            raise ValueError("El precio admite máximo dos decimales")
        return cents / 100
    if key in COLORS:
        if not isinstance(value, str) or not re.fullmatch(r"#[0-9a-fA-F]{6}", value):
            raise ValueError("Color hexadecimal inválido: " + key)
        return value.lower()
    if key in LINKS:
        if not isinstance(value, str) or len(value) > 250:
            raise ValueError("Enlace inválido")
        url = urlparse(value)
        if (url.scheme != "https" or url.hostname not in
                ("discord.com", "www.discord.com", "discord.gg", "www.discord.gg")
                or url.username or url.password or not url.path or
                url.query or url.fragment):
            raise ValueError("Solo se permiten enlaces HTTPS oficiales de Discord")
        return value
    raise ValueError("Campo no permitido: " + str(key)[:70])

def handle_write(handler, data, db, lock, now, role, rate):
    if not rate("site-editor:" + handler.client_address[0], 15, 60):
        return handler.respond(429, {"error": "Demasiadas ediciones, inténtalo después"})
    action = data.get("action", "save")
    if action == "reset":
        if role != "admin":
            return handler.respond(403, {"error": "Solo el administrador puede restaurar el sitio"})
        with lock:
            db.execute("DELETE FROM site_content")
            db.execute("INSERT INTO site_edit_log(actor,changed_keys,updated_at) VALUES(?,?,?)",
                       (role, "RESTORE_DEFAULTS", now()))
        return handler.respond(200, snapshot(db, lock))
    if action != "save":
        return handler.respond(400, {"error": "Acción no permitida"})
    values = data.get("values")
    if not isinstance(values, dict) or not 1 <= len(values) <= len(DEFAULTS):
        return handler.respond(400, {"error": "Campos de edición inválidos"})
    try:
        normalized = {name: validate(name, value) for name, value in values.items()}
    except (ValueError, TypeError) as exc:
        return handler.respond(400, {"error": str(exc)})
    timestamp = now()
    with lock:
        db.execute("BEGIN IMMEDIATE")
        try:
            for name, value in normalized.items():
                db.execute("""INSERT INTO site_content(name,value_json,updated_at,updated_by)
                    VALUES(?,?,?,?) ON CONFLICT(name) DO UPDATE SET
                    value_json=excluded.value_json,updated_at=excluded.updated_at,
                    updated_by=excluded.updated_by""",
                    (name, json.dumps(value, ensure_ascii=False), timestamp, role))
            db.execute("INSERT INTO site_edit_log(actor,changed_keys,updated_at) VALUES(?,?,?)",
                       (role, ",".join(sorted(normalized)), timestamp))
            db.execute("COMMIT")
        except Exception:
            db.execute("ROLLBACK")
            raise
    return handler.respond(200, snapshot(db, lock))

def history(handler, db, lock):
    session = handler.session()
    if not session or session["role"] != "admin":
        return handler.respond(403, {"error": "Solo administrador"})
    with lock:
        rows = db.execute("SELECT actor,changed_keys,updated_at FROM site_edit_log ORDER BY id DESC LIMIT 30").fetchall()
    return handler.respond(200, {"edits": [dict(row) for row in rows]})
