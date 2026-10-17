# AMRight · web app

Flutter web app for AMRight. State with `flutter_bloc`, routing with `go_router`, and our own
small design system on Flutter and Material primitives. The look follows the design canvas
"AM Right — designs" (v2 app screens, v3 chat, mobile).

## Run

```bash
flutter pub get
flutter run -d chrome --web-port 8080 --dart-define=API_BASE=http://localhost:8000  # real backend
flutter run -d chrome --dart-define=FIXTURES=true                                   # saved responses, no backend
flutter analyze && flutter test
```

The backend's CORS default allows `http://localhost:8080`; use another port with `CORS_ORIGINS`.

## Layout

```
lib/
  main.dart            restores the session, starts the app
  app/                 config (dart-defines), app wiring, router + CatalogActions
  ds/                  design system: tokens, typography, theme, responsive, components
  core/
    api/transport.dart HttpTransport and FixtureTransport (assets/fixtures)
    models/            typed mirrors of backend/app/models and vocab.py
    repository.dart    one typed method per backend function, cached by query
    query/             QueryCubit + QueryView: load a query, keep old data while reloading
    format.dart        percentages, ranges, dates, plain-language prior weight
  session/             demo users (no passwords) and SessionCubit (user + replay as_of)
  catalog/             widgets the AI, a dashboard or a page can place by name + params
                       (default_catalog.dart lists all 17; widgets/ holds one file each)
  features/
    login/ doctor/     demo login; patient form → answer page
    hygiene/ lab/      what is spreading; alert inbox + investigation
    research/          Explore: filters, trend chart, table, CSV export
    chat/              ChatCubit, ChatAgent (ScriptedAgent today), answer rendering, composer
    dashboard/         pinned widgets (/v1/dashboard)
    components/        /components: every catalog widget and chat block, live
    shell/             AppPage (phoneBar slot), top bar, replay slider
```

## Rules of the road

- **Design tokens only.** Colors, spacing, radii, shadows and type come from `ds/`; features
  never write a hex or a font size that is not in the design.
- **Catalog widgets take params, not numbers.** Each entry in `catalog/` parses JSON params into
  a query model and loads its own data through `QueryView`. The same builder serves pages,
  pinned cards and (later) chat via `WidgetSlot`. Names and JSON schemas live in
  `backend/app/widgets/catalog.py` (`GET /v1/widgets`): add a widget there and in
  `catalog/default_catalog.dart` together. A GenUI `CatalogItem` wraps an entry's `builder`.
- **The chat places catalog widgets, never numbers.** An answer is a list of `AnswerPart`s
  (widget placements, a clarifying question, "In short"); `ChatAgent` streams them.
  `ScriptedAgent` is the stand-in; the Claude agent maps its A2UI messages to the same events.
- **Widgets never import the router.** They call `CatalogActions` (open an answer, an alert,
  ask the chat); the app implements it with go_router.
- **The replay date is global.** `QueryView` stamps every query with the session's `as_of`
  unless the params set one, and reloads when it changes.
- **Equal-height rows** use `AutoGrid` / `FlexSplit` (built on `EqualRow`), not
  `IntrinsicHeight`.
- Fonts (Sora, Inter) are bundled in `assets/google_fonts`; runtime fetching is off.
- Refresh fixtures from the backend when a contract changes (see `test/models_test.dart` for
  the files it expects).
