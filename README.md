# ddev-allure

One [Allure](https://allurereport.org/) server shared by all DDEV projects, based on
[allure-docker-service](https://github.com/fescobar/allure-docker-service) (API, Allure 2 CLI, history)
and its UI. Test runs push their results; every project gets its own Allure project with history.

## Install

```bash
ddev add-on get CandoImage/ddev-allure   # in any project that runs tests
ddev allure start
```

The add-on only adds the `ddev allure` command and a compose file. The services run as their own compose
project `ddev-allure` on the shared `ddev_default` network, so they are independent of the project that
started them: `ddev stop` / `ddev start` of a project doesn't touch them, and installing the add-on in
several projects still gives one server.

| Command | |
| --- | --- |
| `ddev allure start` | start the server, add the router route |
| `ddev allure stop` | stop the server, remove the route (results are kept) |
| `ddev allure status` | container status |
| `ddev allure open` | open the UI |
| `ddev allure purge` | stop and delete all results |

## URLs

| | From the host | From DDEV containers |
| --- | --- | --- |
| UI | `https://allure.ddev.site[:router https port]` or `http://localhost:5252` | — |
| API | `https://allure-api.ddev.site[:port]` or `http://localhost:5050` | `http://ddev-allure:5050` |

The router route is written to `~/.ddev/traefik/custom-global-config/ddev-allure.yaml` (DDEV copies it to
the router on every `ddev start`; `ddev allure start` also loads it right away). It uses the HTTPS port of
the project you ran `ddev allure start` in. The UI calls the API from the browser via `http://localhost:5050`
(`ALLURE_PUBLIC_API_URL` to change).

## Pushing results

Anything that can reach the server can push Allure results (Allure 2 / Allure 3 `*-result.json`, attachments,
`environment.properties`) through the
[allure-docker-service API](https://github.com/fescobar/allure-docker-service#api); each `project_id` gets
its own report and history:

```bash
# From a DDEV container (the API is also on http://localhost:5050 on the host).
files=(); for f in allure-results/*; do files+=(-F "files[]=@$f"); done
curl -s -X POST "http://ddev-allure:5050/send-results?project_id=my-project&force_project_creation=true" "${files[@]}"
curl -s "http://ddev-allure:5050/generate-report?project_id=my-project"
```

Push from a container on the `ddev_default` network (all DDEV services are). The ports are bound to
`127.0.0.1`, so `host.docker.internal:5050` does **not** work on Linux; use `ddev-allure`.

## Configuration

Environment variables when running `ddev allure start`: `ALLURE_API_PORT` (5050), `ALLURE_UI_PORT` (5252),
`ALLURE_PUBLIC_API_URL`, `ALLURE_KEEP_HISTORY_LATEST` (25), `TZ`.

## Notes

- `ddev poweroff` was not tested yet: the containers aren't DDEV project containers (no `com.ddev.site-name`
  label), so they should keep running.
- The API image is maintained (2.44.0, 2026-07); the UI image's last release is 7.0.3 (2021).
