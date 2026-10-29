# Plan de puesta al día de la app Flutter por tandas (29/10/2026)

Origen: comparación web ↔ app del 29/10/2026. Se miró qué rutas del backend llama cada cliente y qué
pantallas tiene cada uno. Ese día los tres repos locales estaban al día con GitHub: app en la rama
`v7` (`5e0c0f9`, último push el 12/10), web y backend en `main`.

Este plan **amplía** el que ya hay en la app (`docs/plan-web-a-app/index.html`, 14 fases, escrito el
12/10). Las fases 0-2 de aquel (base de IA y resúmenes activos) ya están hechas. Aquí se añade lo que la
web ha sacado después del 12/10 y los huecos que aquel plan no veía (flashcards, mazos, panel, reportes).
También se encaja con el **plan de Studio por tandas** (26/10), porque algunas piezas de la app tienen que
esperar a que la web y el backend las dejen firmes.

**Copia en el repo de la app:** `docs/PLAN-PUESTA-AL-DIA.md` (rama `v7`), para que el otro ordenador la
tenga. Al cerrar cada tanda se actualizan las dos.

**Estado:** tandas 0, 1 y 2 hechas el 29/10/2026, salvo la prueba en el teléfono.

## Resumen del orden

| Fase | Tanda | Qué | Por qué en este puesto |
|---|---|---|---|
| 1. Cimientos | 0 | Punto de partida verde | Sin línea base no se sabe qué rompe cada tanda |
| 2. Lo que ya usa la gente | 1 | IA con créditos y carpetas | La IA de la app ya gasta créditos sin enseñar precio |
| | 2 | Flashcards al día | Mayor distancia en algo de uso diario |
| | 3 | Resúmenes activos al día | Están a medias: falta lo que salió el 10/10 |
| | 4 | Reportar pregunta y bandeja de avisos | Poco código y mucho valor (calidad del banco) |
| | 5 | Mazos y Panel al día | Huecos pequeños en pantallas ya hechas |
| | 6 | Simulacro inteligente | La web lo tiene desde septiembre |
| 3. Contenido | 7 | Biblioteca real y guías de estudio | En la app «Apuntes» es una maqueta |
| | 8 | Tutoriales de la mascota | Primera vez guiada, como en la web |
| | 9 | Electros · Explorador | Hoy solo la Academia, en WebView |
| 4. Juegos | 10 | MedGuess | No depende de nada |
| | 11 | Minijuegos (GramSwipe) | No depende de nada |
| 5. Lo grande | 12 | Mapas · lista, visor y modo estudio | Espera a la tanda 6 de Studio |
| | 13 | Mapas · editor | Decidir nativo o excepción |
| | 14 | Mapas con IA y flashcards con IA | Necesita las tandas 1, 2 y 12 |
| | 15 | Zen | Espera a la tanda 8 de Studio |
| 6. Cierre | 16 | Simulacro con tirada y reanudar | Espera a la tanda 3 de Studio |
| | 17 | Publicación | Versión, firma y tiendas |

## Reglas que valen para todas las tandas

1. **Una tanda cada vez**, y no se empieza la siguiente hasta que la anterior esté subida a `v7` y probada
   en un Android de verdad.
2. **Dónde se trabaja.** En esta máquina, en `mirdailyapp\v6` con la rama `v7`. **Antes de cada tanda:**
   `git pull`, por si hay trabajo nuevo del otro ordenador. **Al terminar:** commit y `git push origin v7`,
   para que el otro ordenador lo baje. Nunca dos ordenadores con la misma tanda a la vez.
3. **La app no tiene lógica propia.** SRS, corrección, precios y permisos los decide el backend. La app
   solo muestra y llama a la API. Si algo hace falta en servidor, va al backend (regla de validar en
   backend), con el orden SQL → backend → app.
4. **La API solo crece** (regla 3 del plan de Studio). Si una tanda de la app necesita una ruta nueva, se
   añade sin cambiar las que ya usan la web y la app instalada.
5. **La web es la referencia.** Antes de portar una pantalla se lee su código en
   `FRONTEND CORRECTO POR INTEGRAR 19.04.2026` y la ruta en `mir-daily-backend-clone`. Nunca se inventa un
   contrato.
6. **Marca.** Kit sticker (`lib/shared/sticker/`), Lexend, curva `Cubic(.22,1,.36,1)`, respetar
   `disableAnimations`, responsive 600/1024. Iconos Material (no Lucide).
7. **Cada tanda deja tests** (`test/`) que fallarían sin el cambio, y deja en verde `flutter analyze` y
   `flutter test`.
8. **Nada de WebView** salvo lo que ya lo es (Academia de Electros) o lo que se decida aquí como excepción.

## Plantilla de verificación (se rellena en cada tanda)

- [ ] `git pull` al empezar, sin conflictos con el otro ordenador.
- [ ] `flutter analyze` sin avisos nuevos; `flutter test` en verde.
- [ ] APK de depuración instalado en un Android: caso feliz y casos límite de la tanda.
- [ ] Mismos números que la web con la misma cuenta (recuentos, saldo, previsión…).
- [ ] Smoke de lo que ya había: login, daily, simulacro, un mazo y Versus.
- [ ] Commit y push a `v7`; memoria y este plan actualizados.

---

# Fase 1 · Cimientos

## Tanda 0 — Punto de partida verde

- Confirmar con el otro ordenador que no queda nada sin subir después del 12/10.
- `flutter pub get`, `flutter analyze` y `flutter test` (hay 79 ficheros de test): anotar la línea base.
  Lo que ya falle se apunta como preexistente; no se arregla aquí salvo que sea trivial.
- APK de depuración instalado y smoke a mano de lo de la plantilla, contra producción.
- Revisar los tres clientes HTTP (`api_service.dart`, `resumenes_api.dart`, `ia_service.dart`): cómo
  renuevan el token y cómo tratan los 401 y 429. Las tandas siguientes van a añadir muchas rutas, así que
  hay que elegir uno como patrón. Solo se documenta: refactor no.
- Poner al día `docs/plan-web-a-app/index.html` con una nota que apunte a este plan.

Hecho cuando: hay una línea base escrita y el APK de `v7` funciona en el teléfono.

### Resultado (29/10/2026, en esta máquina)

- **Repo:** `v7` en `5e0c0f9`, al día con GitHub (`git pull`: «Already up to date»).
- **Flutter de esta máquina: 3.47.5 (Dart 3.13.4).** Según `bdd1246`, el otro ordenador usaba 3.44.9.
  Con esa diferencia, `flutter pub get` reescribe `pubspec.lock` (matcher, meta, test_api, vector_math),
  los registrantes de plugins de escritorio y `analysis_options.yaml`. **Decidido el mismo día: manda
  3.47.5.** El lock, `analysis_options.yaml` y el registrante de macOS (le faltaba `file_picker`) se
  suben con los goldens regenerados. Al comparar viejo con nuevo solo cambia el suavizado de las esquinas
  (98 píxeles de 2,2 millones en el golden que más cambiaba). Ahora `flutter test` da **375 en verde**.
- **`flutter analyze`: 0 errores, 4 warnings, 287 info.**
  - Warnings: `assets/guides/` no existe (ver abajo); campos sin usar `_pointerDownPosition`
    (`main_navigation.dart:742`) y `_isPressed` (`studio_card.dart:20`); un import sin usar en
    `test/daily_completed_test.dart`.
  - Info: 214 son obsoletos del SDK nuevo (197 de ellos `withOpacity` → `withValues`, 6 `HasGameRef`).
    El resto son estilo (`prefer_const…`) y 2 `use_build_context_synchronously`
    (`decks_screen.dart:164`).
- **`flutter test`: 350 en verde, 25 en rojo.** Los 25 son **todos goldens** (27 comparaciones de
  imagen; diferencias del 0,00 % al 0,73 %): kit sticker, mazos, premium, niveles, distribución, sobre,
  perfil, guardar en mazo, celebración y creador de simulacros. **Ningún fallo de lógica.** Casi seguro es
  el cambio de versión de Flutter (cambia cómo se pinta). **No se regeneran** hasta decidir la versión:
  si se regeneran aquí, fallarán en el otro ordenador.
- **`flutter build apk --debug`: compila** (215 s, `build/app/outputs/flutter-apk/app-debug.apk`,
  190 MB). Avisa `unable to find directory entry in pubspec.yaml: assets/guides/`, pero termina.
- **Hallazgo: falta trabajo del otro ordenador.** `pubspec.yaml` declara `assets/guides/` («exportadas
  de la web con `tools/export_study_guides.mjs`»). Se coló en el commit `8a153a3` del 10/10, pero **ni la
  carpeta ni el script están en el repo**. Las guías de la app (las «3 de 17» del plan v7) existen solo
  en el otro ordenador. Hay que subirlas desde allí; también sirven de punto de partida para la tanda 7.
- **Prueba en el teléfono: pendiente.** En esta máquina no hay ningún Android conectado ni emulador.
- **Clientes HTTP** (`api_service.dart`, `resumenes_api.dart`, `ia_service.dart`):
  - Los tres sacan el token de un único sitio (`ApiService.validToken`, cableado en `main.dart`). Bien.
  - **El patrón para las tandas nuevas** es el de `ResumenesApi`/`IaService`: un cliente pequeño por
    área, con el token inyectado y un error propio. Así irán `CreditosApi`, `CarpetasApi`, etc.
    `api_service.dart` no se agranda más.
  - **Riesgo 1:** solo se renueva el token si caduca *según el reloj del móvil*. Si el servidor responde
    401 (sesión cerrada o reloj desfasado), nadie renueva y reintenta. Hay que arreglarlo **antes de la
    tanda 2 de Studio** (sesión verificada en el servidor): un 401 → renovar una vez → reintentar.
  - **Riesgo 2:** si varias peticiones salen a la vez con el token caducado, cada una llama a
    `refresh` por su cuenta. Hay que compartir una sola renovación en curso.
  - **Menores:** ni `IaService.estado` ni la parte sin streaming tienen timeout; ningún cliente trata
    el 429 aparte (enseña el `error` del servidor, que ya viene en castellano).

# Fase 2 · Lo que ya usa la gente

## Tanda 1 — IA con créditos y carpetas

Hoy la app genera resúmenes con IA llamando a `/api/admin/resumenes-ia`. No manda `creditosAnunciados`
ni `idempotencyKey` (son opcionales, así que funciona), pero el usuario **no ve el precio ni su saldo**.

- **Saldo:** `GET /api/ia/saldo`, a la vista donde se crea con IA y en el Perfil.
- **Precio antes de generar:** `GET /api/ia/tarifa`. Mandar `creditosAnunciados` (lo que se enseñó) e
  `idempotencyKey` (un UUID por intento, que se reutiliza al reintentar).
- **Errores con su mensaje:** 403 `sin_plan`, 402 `sin_creditos`, 409 `precio_cambiado` (volver a
  enseñar el precio), 409 `repetida` y 429 `user_usd`. Tras generar, mostrar lo cobrado y lo devuelto
  (`cobrados`, `devueltos`, `saldo`).
- **Cancelar:** `POST /api/ia/cancelar/:usageId`, con las cancelaciones gratis que quedan.
- **Página de créditos en el Perfil:** `GET /api/ia/movimientos` (como `/profile/creditos` en la web),
  con la moneda del fago.
- **Carpetas:** al crear con IA, «Dónde lo guardamos», con sugerencia (`GET /api/carpetas/arbol`). El
  grupo se guarda con `folder_subject_id` y `folder_topic_id`.
- **Mirar en la web:** `src/lib/ia/*`, `src/components/ia/*` (PrecioIA, ProgresoIA, el kit `crear`),
  `src/lib/carpetas/*` y `src/app/profile/creditos`.

Hecho cuando: con una cuenta con plan se ve el precio, se genera, el saldo baja lo mismo que en la web y
el grupo aparece en su carpeta en la web. Con una cuenta sin plan sale el mensaje correcto y no se cobra
nada.

### Resultado (29/10/2026)

- **Era un fallo en producción, no solo un hueco.** `ia_reservar` rechaza con `precio_cambiado` cualquier
  generación sin `creditosAnunciados` (`sql/2026-10-creditos-ia.sql:374`). Con los créditos encendidos
  desde el 16/10, **crear resúmenes con IA desde la app fallaba siempre**. Queda arreglado en cuanto se
  instale el APK nuevo.
- **Nuevo:**
  - `core/models/creditos_ia.dart`: tarifa, precio, saneado de caracteres, saldo, historial y textos.
    Es puerto de `lib/ia/precio.ts` y `creditosTexto.ts`.
  - `core/services/creditos_ia_service.dart`: `CreditosApi` y el almacén `CreditosIa`, que es por cuenta
    y se olvida al cambiar de usuario.
  - `core/services/carpetas.dart`: árbol, mover y sugerencia de carpeta, puerto de `sugerir.ts`.
  - `shared/ia/precio_ia.dart` y `shared/ia/destino_carpeta.dart`: los reutilizarán flashcards y mapas
    con IA.
  - `features/profile/screens/creditos_screen.dart`, con su entrada «Créditos de IA» en el Perfil.
- **Crear resúmenes con IA:**
  - Precio y saldo antes de generar; el botón se desactiva si no llega el saldo o no hay plan.
  - Cobro con `idempotencyKey`, evento `reserva` y botón «Cancelar» (avisa al servidor antes; con el
    aviso de la web si ya no quedan cancelaciones gratis).
  - Errores 402, 403 y 409 con su mensaje y lo devuelto.
  - «Dónde lo guardamos» con la carpeta sugerida por el título. Se aplica al grupo **nuevo** con
    `PATCH /api/carpetas`; si se guarda en un grupo existente, no se mueve, igual que en la web.
- **Pruebas:** 24 nuevas, con la misma tarifa y los mismos números que `test/creditosIA.test.ts` de la web.
  La sugerencia de carpeta se prueba contra el mismo catálogo real (`test/fixtures/catalogo-2026-10-16.json`)
  y propone exactamente lo mismo. La página de créditos se prueba en móvil y tablet sin desbordes.
  `flutter test`: **399 en verde**. `flutter analyze`: sin avisos nuevos.
- **Diferencia consciente con la web:** Dart no normaliza a NFC, así que con un texto descompuesto la app
  cuenta algún carácter de más. El precio anunciado puede pasarse por arriba (el servidor cobra lo suyo),
  pero nunca quedarse corto.
- **No probado todavía:** generar de verdad desde el teléfono con una cuenta con plan (no hay Android en
  esta máquina). Cuando se pruebe, comparar el saldo con `/profile/creditos` de la web.
- **Queda para otras tandas:** «Más» y «Rehacer» de la vista previa (tanda 3; `ResumenesIa.mas` y
  `rehacer` aún no mandan cobro, y ninguna pantalla los usa), «Qué parte usar» y el modo libro.

## Tanda 2 — Flashcards al día

Hoy la app registra el repaso con la ruta de mazos (`/decks/:id/log`, sí/no).

- **Cuatro grados** (1 Otra vez, 2 Difícil, 3 Bien, 4 Fácil), con su intervalo, mediante
  `POST /flashcard-decks/:id/log` (`grade`, `timeSpent`).
- **Deshacer** el último repaso: `POST /flashcard-decks/:id/undo`.
- **Ajustes de la sesión al pulsar Estudiar:** cuántas, falladas, pendientes o nuevas, temas y
  dificultad.
- **Dificultad y escalera:** insignia de nivel, editarla, candados por tema y «Has desbloqueado…»
  (`GET /flashcard-decks/:id/ladder`).
- **Previsión y estado:** `GET /flashcards/forecast` y `GET /flashcards/stats`.
- **Gestión:** crear muchas a la vez (`/cards/bulk`) y mover, copiar o borrar en bloque
  (`/flashcard-cards/move|copy|bulk-delete`).
- **Lista tipo Anki:** asignaturas en lista, con índice y ruta completa.
- **Corregir desde el estudio** y ver de dónde sale la tarjeta. Abrir la rama del mapa queda para la
  tanda 12.
- **Mirar en la web:** `src/app/flashcards/*`, `src/components/flashcards/*` y `src/lib/flashcards/*`.
- **Ojo:** la tanda 12 de Studio añadirá a la web el filtro por asignatura y tema y el Smart Review de
  flashcards. Si ya está hecha cuando lleguemos, entra aquí; si no, se apunta para después.

Hecho cuando: un repaso en la app y otro en la web dejan la tarjeta con la misma fecha siguiente, y la
previsión sale igual en las dos.

### Resultado (29/10/2026, commit `cb8dc98` en v7)

- **Fallo de producción corregido:** la app registraba el repaso en `/decks/:id/log` (sí/no, escalera de
  tres intervalos) y la web en `/flashcard-decks/:id/log` con grado FSRS: la misma tarjeta quedaba con
  fechas distintas según dónde se repasara. Ahora la app usa la ruta de la web y la fecha la pone el servidor.
- **Hecho:** cuatro notas con su intervalo (los manda el servidor con cada tarjeta), deshacer (también con
  la sesión acabada), barra de avance, editar y borrar desde el estudio, «Ver de dónde sale» (sin abrir la
  rama del mapa), resumen final con reparto y «Has desbloqueado…». Ajustes de la sesión (guardados por
  grupo en el teléfono). Grupo con dominio y cubos, panel de escalera, temas en lista tipo Anki con la ruta
  completa, alta rápida de varias tarjetas con tema y nivel, selección para copiar, mover o borrar, mover a
  carpeta y papelera. Portada con previsión de 30 días, madurez y retención, y asignaturas por categoría
  con buscador, orden y tres columnas.
- **Código:** lógica pura en `lib/core/models/flashcards.dart` (puerto de sesion.ts, escalera.ts,
  subjectVisuals y groupTopics); `matchSubjectKey` y el alias «mosaico» en `mir_weights.dart`.
- **Tests:** 433 en verde (18 de lógica con los casos de la web, 7 de la API y 7 de pantallas en móvil y
  tablet, que destaparon y arreglaron dos desbordes a 360 px).
- **No incluido:** `/cards/bulk` (es de las flashcards con IA, tanda 14); abrir la rama del mapa (tanda
  12); filtro por asignatura y tema y Smart Review (esperan a la tanda 12 de Studio).
- **Falta:** probar en el teléfono que un repaso en la app y otro en la web dan la misma fecha siguiente y
  que la previsión sale igual.

## Tanda 3 — Resúmenes activos al día

- **Acciones en bloque** en la página del grupo: buscador, filtros, orden, y mover o copiar
  (`POST /resumenes/:id/bloque`).
- **Editar el color y el icono** del grupo.
- **Previsión:** `GET /resumenes/prevision` (global) y `GET /resumenes/:id/prevision`.
- **Aviso de lo que toca hoy**, en Biblioteca y en el Panel.
- **Repasar contra el informe 83:** estudio hueco a hueco, «solo huecos fallados», modo escribir y
  `end_resumen_session`. Lo que falte, se hace.
- **Repasar contra el informe 85:** gestos para deslizar, niveles AA y tutorial `resumenes.v1`.
- **Vista previa de la IA (informe 84):** «Más» y «Rehacer», varios borradores, tope por documento.
- **Mirar en la web:** `src/app/resumenes/*` y `src/components/resumenes/*`.

## Tanda 4 — Reportar pregunta y bandeja de avisos

- **Reportar** (`POST /api/reports`) desde el daily, el simulacro, los mazos y los resultados, con el
  mismo formulario que la web. Los reportes llegan al panel `/admin/reportes` de la web.
- **Mis reportes** (`GET /api/reports/mine`) en el Perfil, si la web lo enseña.
- **Bandeja de notificaciones:** `GET /notifications`, el contador de no leídas en la navegación
  (`/unread-count`) y marcar leídas (`/:id/read` y `/read-all`). El recordatorio local se queda como está.

## Tanda 5 — Mazos y Panel al día

- **Mazos:** papelera de preguntas de un mazo y recuperarlas (`/items/trash` y `/items/:id/restore`),
  reordenar mazos (`/decks/reorder`) y rendimiento por asignatura (`/subject-performance`).
- **Actualizar el mazo de fallos** (`/decks/:id/refresh`): **no se porta** hasta revisar la auditoría
  de mazos, que pide no pulsarlo.
- **Panel:** progreso mensual (`/analytics/monthly-progress`) y la pregunta más fallada de la semana con
  su imagen (`/stats/most-failed-week`).
- **Nombre visible:** `POST /profile/display-name`, si la web lo deja editar.

## Tanda 6 — Simulacro inteligente

- `POST /api/simulacro/smart`, con el mismo lanzador que la web (Studio → Simulacro).
- **Ojo** con el widget de «más fallada», que en la web llevaba datos de ejemplo (memoria
  `tutoriales-y-simulacro-inteligente`): comprobar qué enseña con datos reales.

# Fase 3 · Contenido

## Tanda 7 — Biblioteca real y guías de estudio

- Sustituir la lista fija de `library_screen.dart` por el catálogo real por carpetas:
  `GET /carpetas/arbol`, `/recuento`, `/sin-clasificar`, `/asignatura/:id` y `/asignatura/:id/dominio`.
- **Guías de estudio** (hoy 8 en la web): **decisión previa**. Sus datos viven en TypeScript dentro de la
  web (`src/lib/studyGuides/*.ts`). Opciones:
  - (a) Copiarlas a Dart. Rápido, pero son dos copias que se desfasan a cada guía nueva.
  - (b) **Recomendada:** que la web publique cada guía como JSON (generado desde el `.ts` al compilar)
    y la app lo lea. Una sola fuente.
- Pantalla de guía nativa: mapa de temas, previsión, esfuerzo/recompensa y preguntas del MIR comentado,
  con el botón de reportar de la tanda 4.

## Tanda 8 — Tutoriales de la mascota

- Mismo sistema que la web: guiones (`src/lib/tutorials/scripts.ts`), superposición con la mascota y
  estado guardado en el servidor (`POST`/`DELETE /profile/tutorials`), para que lo visto en la web no
  vuelva a salir en la app.
- Las poses ya normalizadas están en Escritorio/…texturas…/Poses.

## Tanda 9 — Electros · Explorador

- El explorador de 12 derivaciones de la web (`ExploradorClient.tsx`, `EcgCanvases.tsx`): nativo con
  `CustomPainter`.
- El progreso guardado de la Academia llega con la tanda 12 de Studio; se adapta cuando exista.

# Fase 4 · Juegos

## Tanda 10 — MedGuess
- `GET /medguess/today`, `POST /medguess/attempt` y `GET /medguess/result`. Pantalla del wordle médico
  diario, con háptica y sonido.

## Tanda 11 — Minijuegos (GramSwipe)
- Centro de minijuegos y GramSwipe, a partir de `src/components/minijuegos/gramswipe`.

# Fase 5 · Lo grande

## Tanda 12 — Mapas · lista, visor y modo estudio
- **Espera a la tanda 6 de Studio** (columna `summary`, cuotas y bloqueo optimista). Hasta entonces la
  lista descarga los mapas enteros, y la app heredaría el problema.
- Lista con miniaturas, búsqueda, orden, filtro por asignatura y carpeta, y papelera. Visor de solo
  lectura y modo estudio (tapar hojas y destapar celdas de tabla). Los mapas se leen de la tabla
  `mind_maps` de Supabase, como en la web: no hay backend. Etiquetas siempre saneadas (memoria
  `mapas-label-html-saneado`).

## Tanda 13 — Mapas · editor
- **Decisión al empezar:** editor nativo completo, editor reducido (texto, ramas, plegar) o editarlo solo
  en la web. Es la pieza más cara de todo el plan.

## Tanda 14 — Mapas con IA y flashcards con IA
- Documento → mapa (`/api/admin/mapas-ia`) y rama con IA (`/rama`). Documento o mapa → flashcards
  (`/api/admin/flashcards-ia`) y «Más de este tema». Todo con los créditos de la tanda 1.
- Si para entonces está hecha la tanda 7 de Studio (IA en segundo plano), la app encola y recoge el
  resultado, en vez de esperar con la pantalla abierta.

## Tanda 15 — Zen
- **Espera a la tanda 8 de Studio** (canales privados, denunciar y bloquear). Sustituye a
  `features/focus/`, que es código muerto.

# Fase 6 · Cierre

## Tanda 16 — Simulacro con tirada y reanudar
- **Espera a la tanda 3 de Studio.** La app pasa a `POST /simulacro/start`, guardado por lotes
  (`/simulacro/answers`) y «Tienes un simulacro a medias» (`/simulacro/active`). Cuando la app
  actualizada esté publicada, se puede cerrar el camino viejo del backend.

## Tanda 17 — Publicación
- Número de versión (hoy `1.0.0+1`), `applicationId` definitivo (`com.mirdaily.app`), firma de
  publicación (no la de depuración), textos legales y fichas de tienda.
- El `android:label` del `AndroidManifest.xml` sigue siendo «MIRDaily v5»: cambiarlo a «MIRDaily».
- Antes, borrar el código muerto (`features/focus/` y `studio/screens/studio_screen.dart`) y quitar
  los obsoletos del SDK (`withOpacity` y compañía).

---

## Decisiones pendientes (y cuándo hacen falta)

| Decisión | Hace falta en |
|---|---|
| Subir desde el otro ordenador `assets/guides/` y `tools/export_study_guides.mjs` | Ya (rompe el aviso del build) |
| ~~Versión de Flutter común~~ **Decidido 29/10/2026: 3.47.5.** Fijada en `pubspec.yaml` (`flutter: ">=3.47.5"`), goldens regenerados y 375 tests en verde. El otro ordenador tiene que hacer `flutter upgrade` | Hecho |
| Arreglar el 401 → renovar y reintentar en los clientes | Antes de la tanda 2 de Studio |
| Guías: copiar a Dart o publicarlas como JSON desde la web | Tanda 7 |
| Qué se hace con «Actualizar» en el mazo de fallos | Tanda 5 |
| Editor de mapas nativo, reducido o solo en web | Tanda 13 |
| Cuentas de tienda (Google Play / App Store) y quién firma | Tanda 17 |

## Fuera de este plan
- **Páginas de aterrizaje** (editorial, sinapsis, recta-final, atlas, cozy, goo, landings): no son
  funciones de usuario.
- **Paneles de administración** (`/admin/reportes`, `/admin/creditos`): se quedan solo en la web.
- **Selector de planes del onboarding:** las dos versiones son maquetas. Se decide cuando haya pagos.
