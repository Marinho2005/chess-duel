#!/bin/sh
set -eu

# Volumes sao montados como root. Preparar somente no start, nao no pre-deploy eval.
if [ "${2:-}" = "start" ]; then
  case "${UPLOADS_DIR:-}" in
    /*) ;;
    *) echo 'UPLOADS_DIR must be an absolute path' >&2; exit 1 ;;
  esac
  UPLOADS_DIR=$(readlink -m "$UPLOADS_DIR")
  export UPLOADS_DIR
  if [ "$UPLOADS_DIR" = / ]; then
    echo 'UPLOADS_DIR cannot be root' >&2
    exit 1
  fi
  mkdir -p "$UPLOADS_DIR/avatars" "$UPLOADS_DIR/clubs"
  if [ "$(id -u)" = 0 ]; then
    chown chessduel:chessduel "$UPLOADS_DIR" "$UPLOADS_DIR/avatars" "$UPLOADS_DIR/clubs"
  fi
fi
if [ "$(id -u)" = 0 ]; then
  exec gosu chessduel "$@"
fi
exec "$@"
