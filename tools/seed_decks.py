# Siembra mazos de prueba en una cuenta, con bios variadas y preguntas dentro.
#
#   python tools/seed_decks.py                       # cuenta admin@admin.com
#   python tools/seed_decks.py --user admin2         # cuenta admin2@admin2.com
#   python tools/seed_decks.py --user admin2 --borrar
#
# Solo usa la API pública del backend, las mismas llamadas que hace la app, así
# que no escribe en la base de datos por debajo ni se salta ninguna validación.
#
# Las bios NO son de relleno: cada una cubre un caso que ya ha roto algo o que
# puede romperlo — sin bio, bio de dos líneas justas, bio que se pasa de largo,
# y una sin espacios (el caso que desbordaba la tarjeta de la galería).
import argparse
import json
import random
import sys
import urllib.error
import urllib.request

SUPABASE = 'https://piodbnhiwgntpjxbqqlw.supabase.co'
ANON = (
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBp'
    'b2Ribmhpd2dudHBqeGJxcWx3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk3OTc2NDUsImV4'
    'cCI6MjA4NTM3MzY0NX0.PTmWbzBil0IZPv_iwidP8PCcda9OXR3iWvNuiqfuEqs'
)
API = 'https://mir-daily-backend-production.up.railway.app'

CUENTAS = {
    'admin': ('admin@admin.com', 'adminpassword123'),
    'admin2': ('admin2@admin2.com', 'admin2password123'),
}

PREFIJO = 'Perf '
GRADIENTES = ['apricot', 'slate', 'ember', 'violet',
              'inferno', 'sage', 'blueMist', 'blueNight']

# (sufijo del nombre, bio, nº de preguntas, de dónde salen)
#   'test'  -> las 8 de la asignatura ZZZ de casos límite
#   'mixto' -> preguntas normales al azar
PLANTILLA = [
    ('Casos límite',
     'Las 8 preguntas raras: enunciado kilométrico, imágenes rotas y anuladas.',
     8, 'test'),
    ('Cardio que se me atraganta',
     'Lo que voy fallando en las simulaciones largas.',
     35, 'mixto'),
    ('Sin bio a propósito',
     None,
     11, 'mixto'),
    ('Bio de dos líneas justas',
     'Repaso rápido de antes de dormir, cuando ya no doy para más.',
     9, 'mixto'),
    ('Bio que se pasa de largo',
     'Una descripción bastante más larga de lo razonable, para comprobar que '
     'se corta en dos líneas y no empuja nada fuera de la tarjeta.',
     35, 'mixto'),
    ('Bio sin espacios',
     'pseudopseudohipoparatiroidismoconhipercolesterolemiafamiliarhomocigota',
     7, 'mixto'),
    ('Vacío del todo',
     'Este no tiene ni una pregunta, para ver el estado vacío.',
     0, 'mixto'),
    ('Mazo largo',
     'Con bastantes preguntas, para probar el paginado de "Ver más".',
     60, 'mixto'),
    ('Otro más',
     None,
     12, 'mixto'),
    ('El décimo',
     'Para que la galería tenga suficientes tarjetas que scrollear.',
     10, 'mixto'),
]

# En cuántos mazos se simula historial de estudio para que tengan un % de
# Dominio real. Hace falta pasar de 25 respuestas: por debajo, la app dice "?"
# (y hace bien, no hay dato suficiente).
# Ojo: un mazo pequeño NO puede llegar a 25 repasos de una sentada. El SRS
# programa cada carta respondida para el futuro, así que la siguiente sesión no
# encuentra nada vencido y devuelve 0. Solo los mazos con >= ~30 cartas cruzan
# el umbral y enseñan un % de Dominio; los pequeños se quedan en "?", que es
# exactamente lo que le pasaría a un usuario real.
MAZOS_CON_HISTORIAL = 3
# Objetivo de repasos. Una sesión sirve cada carta una vez, así que para pasar
# de 25 hay que encadenar varias: con una sola se quedaba en 12-18 y todos los
# mazos seguían mostrando Dominio "?".
REPASOS_OBJETIVO = 32
MAX_SESIONES = 8


def pedir(url, token=None, method='GET', body=None, anon=False):
    cabeceras = {'Content-Type': 'application/json'}
    if anon:
        cabeceras['apikey'] = ANON
    if token:
        cabeceras['Authorization'] = 'Bearer ' + token
    req = urllib.request.Request(
        url, method=method, headers=cabeceras,
        data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            crudo = r.read().decode()
            return r.status, (json.loads(crudo) if crudo else {})
    except urllib.error.HTTPError as e:
        crudo = e.read().decode()
        try:
            return e.code, json.loads(crudo) if crudo else {}
        except ValueError:
            return e.code, {'error': crudo[:120]}


def login(email, password):
    estado, datos = pedir(
        SUPABASE + '/auth/v1/token?grant_type=password',
        method='POST', body={'email': email, 'password': password}, anon=True)
    if estado != 200:
        sys.exit('No se pudo entrar como %s: %s' % (email, datos))
    return datos['access_token']


def preguntas_disponibles(token):
    """Ids de preguntas normales, y los de la asignatura de casos límite.

    Van en DOS consultas filtradas en el servidor a propósito. Pedirlas todas
    de golpe y separarlas aquí no funciona: PostgREST corta cualquier consulta
    sin límite explícito en 1000 filas, y como las de prueba son las últimas
    que se insertaron, se quedaban fuera casi todas — salían 5 de 8, sin ningún
    error. Es el mismo corte de 1000 filas que ya mordió al backend en la
    galería de mazos (informe 44).
    """
    estado, test_rows = pedir(
        SUPABASE + '/rest/v1/questions?year=eq.2099&select=id&order=question_number',
        token=token, anon=True)
    if estado != 200:
        sys.exit('No se pudieron leer las preguntas de prueba: %s' % test_rows)

    estado, normal_rows = pedir(
        SUPABASE + '/rest/v1/questions?year=neq.2099&select=id&limit=1000',
        token=token, anon=True)
    if estado != 200:
        sys.exit('No se pudieron leer las preguntas: %s' % normal_rows)

    return [q['id'] for q in normal_rows], [q['id'] for q in test_rows]


def una_sesion(token, deck_id, cuantas):
    """Una sesión: pide cartas y las responde, unas bien y otras mal."""
    estado, datos = pedir(
        '%s/api/studio/decks/%s/start-session' % (API, deck_id),
        token=token, method='POST', body={'limit': cuantas})
    if estado != 200:
        return 0, 0
    sesion = datos['sessionId']

    hechas = aciertos = 0
    for _ in range(cuantas):
        estado, datos = pedir(
            '%s/api/studio/decks/%s/next?sessionId=%s&mode=normal'
            % (API, deck_id, sesion), token=token)
        if estado != 200 or not datos.get('item'):
            break
        item = datos['item']
        correcta = (item.get('questions') or {}).get('correct_answer') or 1
        # ~65 % de aciertos: un dominio creíble, ni perfecto ni desastroso.
        acierta = random.random() < 0.65
        elegida = correcta if acierta else (correcta % 4) + 1
        estado, _ = pedir('%s/api/studio/decks/%s/log' % (API, deck_id),
                          token=token, method='POST',
                          body={'deckItemId': item['id'],
                                'selectedOption': elegida,
                                'sessionId': sesion})
        if estado == 200:
            hechas += 1
            aciertos += 1 if acierta else 0

    pedir('%s/api/studio/sessions/%s/end' % (API, sesion),
          token=token, method='POST')
    return hechas, aciertos


def estudiar(token, deck_id):
    """Encadena sesiones hasta pasar del umbral de Dominio.

    Una sesión sirve cada carta UNA vez, así que en un mazo de 14 preguntas se
    queda en ~16 respuestas y la app sigue diciendo "?" (con razón: el dominio
    se estima con las últimas 25). Se abren sesiones nuevas hasta llegar, o
    hasta que una sesión no sirva ninguna carta.

    Sin esto todos los mazos salían con Dominio "?" y no había forma de ver la
    barra de color ni el orden por "menos dominados".
    """
    hechas = aciertos = 0
    for _ in range(MAX_SESIONES):
        if hechas >= REPASOS_OBJETIVO:
            break
        h, a = una_sesion(token, deck_id, REPASOS_OBJETIVO - hechas)
        if h == 0:
            break
        hechas += h
        aciertos += a
    return hechas, aciertos


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--user', default='admin', choices=sorted(CUENTAS))
    ap.add_argument('--borrar', action='store_true')
    ap.add_argument('--sin-historial', action='store_true',
                    help='no simula sesiones de estudio (mucho más rápido)')
    ap.add_argument('--completar', action='store_true',
                    help='no crea nada: rellena y estudia lo que ya existe')
    args = ap.parse_args()

    email, password = CUENTAS[args.user]
    token = login(email, password)
    print('cuenta: %s' % email)

    estado, datos = pedir('%s/api/studio/decks' % API, token=token)
    if estado != 200:
        sys.exit('No se pudieron leer los mazos: %s' % datos)
    existentes = datos['decks']

    if args.borrar:
        n = 0
        for d in existentes:
            if d['name'].startswith(PREFIJO):
                st, _ = pedir('%s/api/studio/decks/%s/delete' % (API, d['id']),
                              token=token, method='POST')
                print('  papelera  %-36s %s' % (d['name'][:36], st))
                n += 1
        print('%d mazos de prueba enviados a la papelera' % n)
        return

    normales, test = preguntas_disponibles(token)
    print('preguntas disponibles: %d normales, %d de casos límite'
          % (len(normales), len(test)))
    random.seed(20260827)

    if args.completar:
        for d in existentes:
            if not d['name'].startswith(PREFIJO):
                continue
            # El de casos límite debe tener las 8; añadirlas nunca duplica.
            if 'Casos límite' in d['name'] and test:
                pedir('%s/api/studio/decks/%s/items' % (API, d['id']),
                      token=token, method='POST', body={'questionIds': test})
            faltan = REPASOS_OBJETIVO - (d.get('total_reviews') or 0)
            if (d.get('total_items') or 0) >= 5 and faltan > 0:
                hechas, aciertos = estudiar(token, d['id'])
                print('  %-36s +%d respuestas' % (d['name'][:36], hechas))
        estado, datos = pedir('%s/api/studio/decks' % API, token=token)
        print()
        for d in datos['decks']:
            dom = '—'
            if (d.get('total_reviews') or 0) >= 25:
                dom = '%d %%' % round((d.get('accuracy') or 0) * 100)
            print('  %-36s items=%-3s repasos=%-4s dominio=%-5s bio=%s'
                  % (d['name'][:36], d.get('total_items'),
                     d.get('total_reviews'), dom,
                     'si' if d.get('description') else 'no'))
        return

    ya = {d['name'] for d in existentes}
    creados = []

    for i, (sufijo, bio, cuantas, origen) in enumerate(PLANTILLA):
        nombre = '%s%02d · %s' % (PREFIJO, i + 1, sufijo)
        if nombre in ya:
            print('  %s ya existe, se salta' % nombre)
            continue

        estado, datos = pedir('%s/api/studio/decks' % API, token=token,
                              method='POST',
                              body={'name': nombre, 'description': bio})
        if estado != 201:
            print('  ERROR creando %s: %s %s' % (nombre, estado, datos))
            continue
        deck_id = datos['deck']['id']

        metidas = 0
        if cuantas:
            if origen == 'test':
                ids = test[:cuantas]
            else:
                ids = random.sample(normales, min(cuantas, len(normales)))
            estado, _ = pedir('%s/api/studio/decks/%s/items' % (API, deck_id),
                              token=token, method='POST',
                              body={'questionIds': ids})
            metidas = len(ids) if estado == 200 else 0

        gradiente = GRADIENTES[i % len(GRADIENTES)]
        pedir('%s/api/studio/decks/%s/update' % (API, deck_id), token=token,
              method='POST', body={'gradient': gradiente})

        creados.append((nombre, deck_id, metidas))
        print('  %-34s preguntas=%-3d gradiente=%-9s bio=%s'
              % (nombre[:34], metidas, gradiente, 'si' if bio else 'no'))

    # Historial de estudio en unos cuantos, para que tengan Dominio real.
    if not args.sin_historial:
        print('\nsimulando estudio (para que salga el %% de Dominio)...')
        pendientes = MAZOS_CON_HISTORIAL
        for nombre, deck_id, metidas in creados:
            if pendientes <= 0:
                break
            if metidas < 10:
                continue
            hechas, aciertos = estudiar(token, deck_id)
            if hechas:
                print('  %-34s %d respuestas, %d aciertos (%d %%)'
                      % (nombre[:34], hechas, aciertos,
                         round(aciertos / hechas * 100)))
                pendientes -= 1

    estado, datos = pedir('%s/api/studio/decks' % API, token=token)
    print('\nmazos de %s ahora: %d' % (email, len(datos['decks'])))
    for d in datos['decks']:
        dom = '—'
        if (d.get('total_reviews') or 0) >= 25:
            dom = '%d %%' % round((d.get('accuracy') or 0) * 100)
        print('  %-36s items=%-3s repasos=%-4s dominio=%-5s bio=%s'
              % (d['name'][:36], d.get('total_items'),
                 d.get('total_reviews'), dom,
                 'si' if d.get('description') else 'no'))


main()
