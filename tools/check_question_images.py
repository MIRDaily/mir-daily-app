# Comprueba que TODAS las imágenes de preguntas existen de verdad en R2.
#
#   python tools/check_question_images.py
#
# Lee las preguntas con has_image=true de Supabase y pide cada URL. Escribe el
# resultado en tools/imagenes_rotas.csv si hay alguna que falle.
#
# Por qué hace falta: la app da por hecho que si `has_image` es true y hay
# `image_url`, la imagen está. Si el fichero no llegó a subirse al bucket, la
# pregunta enseña un hueco vacío y no hay forma de enterarse desde dentro.
import csv
import json
import os
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

SUPABASE = 'https://piodbnhiwgntpjxbqqlw.supabase.co'
ANON = (
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBp'
    'b2Ribmhpd2dudHBqeGJxcWx3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk3OTc2NDUsImV4'
    'cCI6MjA4NTM3MzY0NX0.PTmWbzBil0IZPv_iwidP8PCcda9OXR3iWvNuiqfuEqs'
)

EMAIL = os.environ.get('MIRDAILY_EMAIL', 'admin@admin.com')
PASSWORD = os.environ.get('MIRDAILY_PASSWORD', 'adminpassword123')


def get_json(url, headers, data=None):
    req = urllib.request.Request(
        url,
        headers=headers,
        data=json.dumps(data).encode() if data is not None else None,
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())


def login():
    return get_json(
        SUPABASE + '/auth/v1/token?grant_type=password',
        {'apikey': ANON, 'Content-Type': 'application/json'},
        {'email': EMAIL, 'password': PASSWORD},
    )['access_token']


def check(q):
    url = q.get('image_url')
    if not url:
        return (q, 'sin url')
    try:
        req = urllib.request.Request(url, method='GET')
        with urllib.request.urlopen(req, timeout=25) as r:
            largo = int(r.headers.get('Content-Length') or 0)
            if r.status != 200:
                return (q, 'http %s' % r.status)
            # Un objeto de 0 bytes se sirve con 200 pero no se puede pintar.
            if largo == 0:
                return (q, 'vacia (0 bytes)')
            return None
    except urllib.error.HTTPError as e:
        return (q, 'http %s' % e.code)
    except Exception as e:                      # noqa: BLE001
        return (q, type(e).__name__)


def main():
    token = login()
    preguntas = get_json(
        SUPABASE + '/rest/v1/questions?has_image=eq.true'
        '&select=id,subject,year,question_number,image_url&limit=5000',
        {'apikey': ANON, 'Authorization': 'Bearer ' + token},
    )
    print('preguntas con imagen: %d' % len(preguntas))

    with ThreadPoolExecutor(max_workers=12) as pool:
        resultados = [r for r in pool.map(check, preguntas) if r]

    if not resultados:
        print('todas las imagenes responden correctamente.')
        return

    destino = os.path.join(os.path.dirname(__file__), 'imagenes_rotas.csv')
    with open(destino, 'w', newline='', encoding='utf8') as f:
        w = csv.writer(f)
        w.writerow(['question_id', 'asignatura', 'anio', 'n_pregunta',
                    'motivo', 'url'])
        for q, motivo in resultados:
            w.writerow([q['id'], q.get('subject'), q.get('year'),
                        q.get('question_number'), motivo,
                        q.get('image_url') or ''])

    print('\nFALLAN %d de %d:' % (len(resultados), len(preguntas)))
    for q, motivo in resultados[:20]:
        print('  %-6s %-34s %s  ->  %s'
              % (q['id'], (q.get('subject') or '')[:34],
                 q.get('year'), motivo))
    if len(resultados) > 20:
        print('  ... y %d mas' % (len(resultados) - 20))
    print('\nlistado completo en %s' % destino)


main()
