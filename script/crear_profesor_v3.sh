#!/bin/bash

# ================================================================
#   Gestion de usuario profesor (Linux + Samba + NAS)
#   Permite crear, eliminar o listar usuarios del sistema
# ================================================================

# Solo root puede ejecutar este script
if [ "$EUID" -ne 0 ]; then
  echo ""
  echo "  ERROR: Este script debe ejecutarse como root"
  echo ""
  exit 1
fi

# Ruta base donde se guardan las carpetas de los profesores en el NAS
BASE="/mnt/nas/profesorado"

# Comprobamos que el NAS este montado antes de continuar
if ! mountpoint -q /mnt/nas; then
  echo ""
  echo "  ERROR: El NAS no esta montado en /mnt/nas"
  echo ""
  exit 1
fi

# ================================================================
#   MENU PRINCIPAL
# ================================================================

echo ""
echo "  =============================================="
echo "   Gestion de usuario profesor"
echo "  =============================================="
echo ""
echo "   1. Crear usuario"
echo "   2. Eliminar usuario"
echo "   3. Listar usuarios"
echo ""
read -p "   Elige una opcion [1/2/3]: " OPCION
echo ""

# ================================================================
#   OPCION 3 - LISTAR USUARIOS
# ================================================================

if [[ "$OPCION" == "3" ]]; then

  echo "  =============================================="
  echo "   Usuarios Linux del sistema (UID >= 1000)"
  echo "  =============================================="
  echo ""

  # Recorremos /etc/passwd mostrando solo usuarios reales (UID >= 1000, excluimos nobody)
  while IFS=: read -r username _ uid _ fullname homedir _; do
    if [ "$uid" -ge 1000 ] && [ "$uid" -ne 65534 ]; then
      printf "  %-20s  UID: %-6s  Home: %s\n" "$username" "$uid" "$homedir"
      [ -n "$fullname" ] && printf "  %-20s  Nombre: %s\n" "" "$fullname"
      echo ""
    fi
  done < /etc/passwd

  echo "  =============================================="
  echo "   Usuarios Samba"
  echo "  =============================================="
  echo ""

  # Listamos los usuarios de Samba y comprobamos si estan habilitados o deshabilitados
  while IFS=: read -r sambuser _ uid _; do
    STATUS=$(pdbedit -Lv "$sambuser" 2>/dev/null | grep "Account Flags" | grep -q "D" && echo "Deshabilitado" || echo "Habilitado")
    printf "  %-20s  UID: %-6s  Estado: %s\n" "$sambuser" "$uid" "$STATUS"
    echo ""
  done < <(pdbedit -L)

  echo "  =============================================="
  echo "   Carpetas en NAS ($BASE)"
  echo "  =============================================="
  echo ""

  # Listamos las carpetas del NAS mostrando el propietario de cada una
  if [ -d "$BASE" ]; then
    for dir in "$BASE"/*/; do
      [ -d "$dir" ] || continue
      nombre=$(basename "$dir")
      propietario=$(stat -c '%U' "$dir")
      printf "  %-20s  Propietario: %s\n" "$nombre" "$propietario"
      echo ""
    done
  else
    echo "  No se encontro la carpeta base en el NAS."
    echo ""
  fi

  exit 0
fi

# ================================================================
#   DATOS DEL USUARIO (opciones 1 y 2)
# ================================================================

read -p "  Usuario del profesor : " USER

# ================================================================
#   OPCION 2 - ELIMINAR USUARIO
# ================================================================

if [[ "$OPCION" == "2" ]]; then

  echo ""
  echo "  Comprobando elementos a eliminar..."
  echo "  ----------------------------------------------"

  # Variables para saber que existe actualmente
  USER_EXISTS=false
  SAMBA_EXISTS=false
  NASDIR_EXISTS=false

  # Comprobamos si existe el usuario Linux
  if id "$USER" &>/dev/null; then
    USER_EXISTS=true
  fi

  # Comprobamos si existe el usuario en Samba
  if pdbedit -L | cut -d: -f1 | grep -qx "$USER"; then
    SAMBA_EXISTS=true
  fi

  # Comprobamos si existe la carpeta en el NAS
  USERDIR="$BASE/$USER"
  [ -d "$USERDIR" ] && NASDIR_EXISTS=true

  # Mostramos el estado actual de cada elemento
  echo ""
  printf "  %-25s : %s\n" "Usuario Linux"   "$USER_EXISTS"
  printf "  %-25s : %s\n" "Usuario Samba"   "$SAMBA_EXISTS"
  printf "  %-25s : %s\n" "Carpeta en NAS"  "$NASDIR_EXISTS"
  echo ""

  # Si no existe ninguno, no hay nada que eliminar
  if ! $USER_EXISTS && ! $SAMBA_EXISTS && ! $NASDIR_EXISTS; then
    echo "  INFO: No se encontro ningun elemento para este usuario."
    echo ""
    exit 0
  fi

  # Si existe la carpeta en el NAS, preguntamos si se quiere conservar
  KEEP_NAS=false
  if $NASDIR_EXISTS; then
    echo "  Se encontro una carpeta en el NAS: $USERDIR"
    read -p "  Deseas conservar la carpeta en el NAS? [s/N]: " KEEP_ANSWER
    echo ""
    if [[ "$KEEP_ANSWER" == "s" || "$KEEP_ANSWER" == "S" ]]; then
      KEEP_NAS=true
    fi
  fi

  # Mostramos lo que se va a eliminar y pedimos confirmacion
  echo "  Se eliminaran los siguientes elementos:"
  $USER_EXISTS                    && echo "   - Usuario Linux (incluido el directorio home)"
  $SAMBA_EXISTS                   && echo "   - Usuario Samba"
  $NASDIR_EXISTS && ! $KEEP_NAS   && echo "   - Carpeta en NAS ($USERDIR)"
  $NASDIR_EXISTS && $KEEP_NAS     && echo "   - Carpeta en NAS : SE CONSERVARA"
  echo ""
  read -p "  Esta seguro de que deseas continuar? [s/N]: " CONFIRM
  echo ""

  if [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" ]]; then
    echo "  Operacion cancelada."
    echo ""
    exit 0
  fi

  # Eliminamos el usuario de Samba si existe
  if $SAMBA_EXISTS; then
    echo "  Eliminando usuario Samba..."
    smbpasswd -x "$USER"
  fi

  # Eliminamos el usuario Linux junto con su directorio home
  if $USER_EXISTS; then
    echo "  Eliminando usuario Linux y su home..."
    userdel -r "$USER" 2>/dev/null
  fi

  # Eliminamos la carpeta del NAS solo si el usuario no pidio conservarla
  if $NASDIR_EXISTS && ! $KEEP_NAS; then
    echo "  Eliminando carpeta en NAS..."
    rm -rf "$USERDIR"
  elif $NASDIR_EXISTS && $KEEP_NAS; then
    echo "  Carpeta en NAS conservada : $USERDIR"
  fi

  echo ""
  echo "  =============================================="
  echo "   USUARIO ELIMINADO CORRECTAMENTE"
  echo "  =============================================="
  echo "   Usuario     : $USER"
  if $NASDIR_EXISTS && $KEEP_NAS; then
    echo "   Carpeta NAS : Conservada en $USERDIR"
  elif $NASDIR_EXISTS; then
    echo "   Carpeta NAS : Eliminada"
  fi
  echo "  =============================================="
  echo ""
  exit 0
fi

# ================================================================
#   OPCION 1 - CREAR USUARIO
# ================================================================

# Pedimos el nombre completo solo al crear
read -p "  Nombre completo      : " NAME

echo ""
echo "  Comprobando estado del sistema..."
echo "  ----------------------------------------------"

# Variables de estado para cada elemento
USER_EXISTS=false
HOME_EXISTS=false
SAMBA_EXISTS=false
NASDIR_EXISTS=false

# Comprobamos el usuario Linux y su home
if id "$USER" &>/dev/null; then
  USER_EXISTS=true
  HOME_DIR=$(getent passwd "$USER" | cut -d: -f6)
  [ -d "$HOME_DIR" ] && HOME_EXISTS=true
fi

# Comprobamos el usuario en Samba
if pdbedit -L | cut -d: -f1 | grep -qx "$USER"; then
  SAMBA_EXISTS=true
fi

# Comprobamos la carpeta del usuario en el NAS
USERDIR="$BASE/$USER"
[ -d "$USERDIR" ] && NASDIR_EXISTS=true

# Mostramos el estado actual de cada elemento
echo ""
printf "  %-25s : %s\n" "Usuario Linux"   "$USER_EXISTS"
printf "  %-25s : %s\n" "Home directory"  "$HOME_EXISTS"
printf "  %-25s : %s\n" "Usuario Samba"   "$SAMBA_EXISTS"
printf "  %-25s : %s\n" "Carpeta en NAS"  "$NASDIR_EXISTS"
echo ""

# Si todo ya esta creado, no hay nada que hacer
if $USER_EXISTS && $SAMBA_EXISTS && $NASDIR_EXISTS; then
  echo "  INFO: El usuario ya esta completamente configurado."
  echo ""
  exit 0
fi

# Mostramos las acciones que se van a realizar y pedimos confirmacion
echo "  Se realizaran las siguientes acciones:"
$USER_EXISTS   || echo "   - Crear usuario Linux"
$SAMBA_EXISTS  || echo "   - Crear usuario Samba"
$NASDIR_EXISTS || echo "   - Crear carpeta en NAS"
echo ""
read -p "  Deseas continuar? [s/N]: " CONFIRM
echo ""

if [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" ]]; then
  echo "  Operacion cancelada."
  echo ""
  exit 0
fi

# Creamos el usuario Linux con home y sin acceso a shell
if ! $USER_EXISTS; then
  echo "  Creando usuario Linux..."
  useradd -m -c "$NAME" -s /usr/sbin/nologin "$USER"
  passwd "$USER"
fi

# Creamos el usuario en Samba y lo habilitamos
if ! $SAMBA_EXISTS; then
  echo "  Creando usuario Samba..."
  smbpasswd -a "$USER"
  smbpasswd -e "$USER"
fi

# Creamos la carpeta del usuario en el NAS
if ! $NASDIR_EXISTS; then
  echo "  Creando carpeta en NAS..."
  mkdir -p "$USERDIR"
fi

# Asignamos permisos: solo el propio usuario puede acceder a su carpeta
echo "  Aplicando permisos..."
chown "$USER:$USER" "$USERDIR"
chmod 700 "$USERDIR"

echo ""
echo "  =============================================="
echo "   OPERACION COMPLETADA"
echo "  =============================================="
echo "   Usuario     : $USER"
echo "   Home        : $(getent passwd "$USER" | cut -d: -f6)"
echo "   Carpeta NAS : $USERDIR"
echo "   Acceso      : Samba"
echo "  =============================================="
echo ""