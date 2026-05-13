#!/bin/bash
# ================================================================
#   gestionar_profesor.sh — Proxmox + NAS QNAP
#   Crea o elimina usuarios profesores en ambos sistemas
#
#   Cambiar el día 18:
#     NAS_IP="192.168.1.200"
#     PROXMOX_IP="192.168.1.100"
# ================================================================

NAS_IP="10.0.86.82"
NAS_IP_ZEROTIER="10.230.74.51"
NAS_USER="admin"
NAS_BASE="/share/CACHEDEV1_DATA/profesores"
NAS_VOLUME_ID="1"
PROXMOX_IP="10.0.20.219"
PROXMOX_NODE="server"

# ----------------------------------------------------------------
# Funciones base
# ----------------------------------------------------------------
ok()  { echo "   OK: $1"; }
err() { echo ""; echo "  ERROR — $1"; echo ""; rollback; exit 1; }
nas() { ssh -o StrictHostKeyChecking=no -o BatchMode=yes "${NAS_USER}@${NAS_IP}" "$1" 2>/dev/null; }

# Rollback: deshace en orden inverso según lo que se haya creado
# ROLLBACK es un string que acumula tags: "nasUser dir share stor pveUser pool"
rollback() {
    [ -z "$ROLLBACK" ] && return
    echo "  Deshaciendo cambios..."
    [[ $ROLLBACK == *pool*    ]] && pveum pool delete "pool_${USUARIO}" 2>/dev/null         && echo "   - Pool eliminado"
    [[ $ROLLBACK == *pveUser* ]] && pveum user delete "${USUARIO}@pve" 2>/dev/null          && echo "   - Usuario Proxmox eliminado"
    [[ $ROLLBACK == *stor*    ]] && pvesm remove "nas-prof-${USUARIO}" 2>/dev/null          && echo "   - Storage eliminado"
    # Limpiar directorio huérfano siempre, aunque pvesm remove haya fallado
    umount -l "/mnt/pve/nas-prof-${USUARIO}" 2>/dev/null
    rm -rf "/mnt/pve/nas-prof-${USUARIO}" 2>/dev/null
    [[ $ROLLBACK == *share*   ]] && nas "/sbin/qcli_sharedfolder -D sharename='${USUARIO}'" && echo "   - Share NAS eliminado"
    [[ $ROLLBACK == *dir*     ]] && nas "rm -rf '${NAS_BASE}/${USUARIO}'"                   && echo "   - Carpeta NAS eliminada"
    [[ $ROLLBACK == *nasUser* ]] && nas "qcli_users -d username='${USUARIO}' sid=${SID}"    && echo "   - Usuario NAS eliminado"
}

# Autenticación NAS — hasta 3 intentos
auth_nas() {
    local INTENTOS=0
    while [ $INTENTOS -lt 3 ]; do
        read -s -p "  Contrasena del admin del NAS: " PASSWORD_ADMIN; echo ""
        SID=$(nas "qcli -l user=${NAS_USER} pw=${PASSWORD_ADMIN} saveauthsid=yes" | grep "sid is" | awk '{print $3}')
        [ -n "$SID" ] && { ok "Autenticacion correcta"; echo ""; return; }
        INTENTOS=$((INTENTOS+1))
        [ $INTENTOS -lt 3 ] && echo "   Incorrecta. Intentos restantes: $((3-INTENTOS))"
    done
    echo "  ERROR: Demasiados intentos fallidos."; exit 1
}

# Espera activa hasta que se cumpla una condición en el NAS
esperar_nas() {
    local INTENTOS=0
    until nas "$1" 2>/dev/null; do
        INTENTOS=$((INTENTOS+1))
        [ $INTENTOS -ge 10 ] && err "$2"
        sleep 2
    done
}

# ----------------------------------------------------------------
# Comprobaciones iniciales
# ----------------------------------------------------------------
[ "$EUID" -ne 0 ]            && { echo "  ERROR: Ejecuta como root"; exit 1; }
command -v pveum &>/dev/null || { echo "  ERROR: pveum no encontrado"; exit 1; }
nas "echo ok" &>/dev/null    || { echo "  ERROR: Sin conexion al NAS. Ejecuta: ssh-copy-id ${NAS_USER}@${NAS_IP}"; exit 1; }

# ----------------------------------------------------------------
# Verificar rol ProfesorRole
# ----------------------------------------------------------------
verificar_rol() {
    pveum role list | grep -q "ProfesorRole" && { ok "Rol ProfesorRole existe"; return; }
    pveum role add ProfesorRole --privs \
        "Datastore.Allocate,Datastore.AllocateSpace,Datastore.AllocateTemplate,Datastore.Audit,\
VM.Allocate,VM.Audit,VM.Clone,VM.Config.CDROM,VM.Config.CPU,VM.Config.Disk,\
VM.Config.Memory,VM.Config.Network,VM.Config.Options,VM.Config.HWType,\
VM.Console,VM.PowerMgmt,VM.Snapshot,SDN.Use" 2>/dev/null \
        || { echo "  ERROR: No se pudo crear ProfesorRole"; exit 1; }
    ok "Rol ProfesorRole creado"
}

# ----------------------------------------------------------------
# Crear profesor
# ----------------------------------------------------------------
crear_profesor() {
    echo ""; echo "  === Crear nuevo profesor ==="; echo ""

    read -p "  Usuario (ej: juan): " USUARIO
    USUARIO=$(echo "$USUARIO" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
    [ -z "$USUARIO" ] && { echo "  ERROR: Nombre vacio"; exit 1; }

    read -p "  Nombre completo: " NOMBRE_COMPLETO
    [ -z "$NOMBRE_COMPLETO" ] && { echo "  ERROR: Nombre completo vacio"; exit 1; }

    echo ""
    while true; do
        read -s -p "  Contrasena (min 8): " PASSWORD; echo ""
        [ ${#PASSWORD} -lt 8 ] && { echo "   Minimo 8 caracteres."; continue; }
        read -s -p "  Confirma contrasena: " PASSWORD2; echo ""
        [ "$PASSWORD" = "$PASSWORD2" ] && break
        echo "   No coinciden."
    done
    echo ""

    auth_nas

    # Comprobaciones previas
    echo "  Comprobando disponibilidad..."
    pveum user list | grep -q "${USUARIO}@pve"  && { echo "  ERROR: Usuario ${USUARIO}@pve ya existe"; exit 1; }
    pveum pool list | grep -q "pool_${USUARIO}" && { echo "  ERROR: Pool pool_${USUARIO} ya existe"; exit 1; }
    [ "$(nas "qcli_users -l 2>/dev/null | grep -c '${USUARIO}'" | tr -d '\n\r')" -gt 0 ] 2>/dev/null \
        && { echo "  ERROR: Usuario ${USUARIO} ya existe en el NAS"; exit 1; }
    [ "$(nas "/sbin/qcli_sharedfolder -l 2>/dev/null | grep -c '[[:space:]]${USUARIO}[[:space:]]*$'" | tr -d '\n\r')" -gt 0 ] 2>/dev/null \
        && { echo "  ERROR: Share ${USUARIO} ya existe en el NAS"; exit 1; }
    [ "$(nas "[ -d '${NAS_BASE}/${USUARIO}' ] && echo si || echo no")" = "si" ] \
        && { echo "  ERROR: Carpeta ya existe en el NAS"; exit 1; }
    ok "Disponible"; echo ""

    # 1. Usuario NAS
    echo "  [1/8] Creando usuario en el NAS..."
    nas "qcli_users -a username='${USUARIO}' password='${PASSWORD}' passwordVerify='${PASSWORD}' SAMBA=1 \
        denyaccess='backups,fog,data,Download,Multimedia,Public,Web,profesores' sid=${SID}" \
        | grep -q "ok" || err "No se pudo crear el usuario en el NAS"
    ROLLBACK="nasUser"
    ok "Usuario ${USUARIO} creado en el NAS"

    # 2. Grupo profesores
    echo "  [2/8] Anadiendo al grupo profesores..."
    nas "qcli_usergroups -U groupname=profesores select_user='${USUARIO}' sid=${SID}" \
        | grep -q "ok" || err "No se pudo añadir al grupo profesores"
    ok "Añadido al grupo profesores"

    # 3. Carpeta privada
    echo "  [3/8] Creando carpeta privada..."
    USUARIO_UID=$(nas "id -u '${USUARIO}' 2>/dev/null")
    PROFESORES_GID=$(nas "grep '^profesores:' /etc/group | cut -d: -f3")
    [ -z "$USUARIO_UID" ]    && err "No se pudo obtener UID del usuario"
    [ -z "$PROFESORES_GID" ] && err "No se pudo obtener GID del grupo profesores"
    nas "mkdir -p '${NAS_BASE}/${USUARIO}' && chown '${USUARIO_UID}:${PROFESORES_GID}' '${NAS_BASE}/${USUARIO}' && chmod 700 '${NAS_BASE}/${USUARIO}'" \
        || err "No se pudo crear la carpeta"
    ROLLBACK="nasUser dir"
    ok "Carpeta /profesores/${USUARIO} creada"

    # 4. Share Samba
    # El QNAP crea el share de forma asíncrona — hay que esperar a que
    # aparezca en smb.conf antes de insertar la línea admin users
    echo "  [4/8] Creando share Samba privado..."
    nas "/sbin/qcli_sharedfolder -s sharename='${USUARIO}' volumeID=${NAS_VOLUME_ID} \
        path_type=manual path='/profesores/${USUARIO}' guest=deny userrw='${USUARIO}' hidden=1" \
        | grep -qE "ok|Please use" || err "No se pudo crear el share Samba"
    esperar_nas "grep -q '\[${USUARIO}\]' /etc/config/smb.conf" \
        "Timeout esperando share en smb.conf"
    nas "sed -i '/\[${USUARIO}\]/a admin users = ${USUARIO}' /etc/config/smb.conf" \
        || err "No se pudo configurar smb.conf"
    ROLLBACK="nasUser dir share"
    ok "Share Samba \\\\${NAS_IP}\\${USUARIO} creado (oculto)"

    # 5. NFS
    # qcli_sharedfolder -N escribe en /etc/exports Y crea /share/NFSv=4/USUARIO
    # El QNAP añade wildcard * con ro y entradas duplicadas — hay que limpiarlos
    echo "  [5/8] Configurando NFS para Proxmox..."
    nas "qcli_sharedfolder -N sharename='${USUARIO}' Access=Enabled" \
        || err "No se pudo habilitar NFS"
    esperar_nas "grep -q '${USUARIO}' /etc/exports" \
        "Timeout esperando /etc/exports"
    nas "sed -i '/${USUARIO}/d' /etc/exports
echo '\"/share/CACHEDEV1_DATA/profesores/${USUARIO}\" ${PROXMOX_IP}(rw,async,no_subtree_check,insecure,no_root_squash)' >> /etc/exports
echo '\"/share/NFSv=4/${USUARIO}\" ${PROXMOX_IP}(rw,nohide,async,no_subtree_check,insecure,no_root_squash)' >> /etc/exports
exportfs -ra" || err "No se pudo limpiar /etc/exports"
    ok "NFS configurado para Proxmox (${PROXMOX_IP})"

    # 6. Storage NFS en Proxmox
    echo "  [6/8] Montando storage NFS en Proxmox..."
    # Limpiar directorio huérfano si existe de intentos anteriores
    [ -d "/mnt/pve/nas-prof-${USUARIO}" ] && {
        umount -l "/mnt/pve/nas-prof-${USUARIO}" 2>/dev/null
        rm -rf "/mnt/pve/nas-prof-${USUARIO}" 2>/dev/null
    }
    local INTENTOS=0
    until showmount -e "$NAS_IP" 2>/dev/null | grep -q "^/${USUARIO} "; do
        INTENTOS=$((INTENTOS+1)); [ $INTENTOS -ge 12 ] && err "Timeout esperando export en showmount"
        sleep 2
    done
    pvesm add nfs "nas-prof-${USUARIO}" \
        --server "$NAS_IP" --export "/${USUARIO}" \
        --content images,rootdir,import 2>/dev/null \
        || err "No se pudo montar el storage NFS"
    ROLLBACK="nasUser dir share stor"
    ok "Storage nas-prof-${USUARIO} montado"

    # 7. Usuario Proxmox
    echo "  [7/8] Creando usuario en Proxmox..."
    pveum user add "${USUARIO}@pve" --password "$PASSWORD" --comment "$NOMBRE_COMPLETO" 2>/dev/null \
        || err "No se pudo crear el usuario en Proxmox"
    ROLLBACK="nasUser dir share stor pveUser"
    ok "Usuario ${USUARIO}@pve creado"

    # 8. Pool y permisos
    echo "  [8/8] Creando pool y asignando permisos..."
    pveum pool add "pool_${USUARIO}" --comment "Pool de $NOMBRE_COMPLETO" 2>/dev/null \
        || err "No se pudo crear el pool"
    ROLLBACK="nasUser dir share stor pveUser pool"
    pveum aclmod "/pool/pool_${USUARIO}"        --user "${USUARIO}@pve" --role ProfesorRole     2>/dev/null || err "Error ACL pool/ProfesorRole"
    pveum aclmod "/pool/pool_${USUARIO}"        --user "${USUARIO}@pve" --role PVEPoolUser      2>/dev/null || err "Error ACL pool/PVEPoolUser"
    pveum aclmod "/storage/nas-prof-${USUARIO}" --user "${USUARIO}@pve" --role ProfesorRole     2>/dev/null || err "Error ACL storage privado"
    pveum aclmod "/storage/nas-recursos"        --user "${USUARIO}@pve" --role PVEDatastoreUser 2>/dev/null || err "Error ACL nas-recursos"
    pveum aclmod "/nodes/${PROXMOX_NODE}"       --user "${USUARIO}@pve" --role PVEVMUser        2>/dev/null || err "Error ACL nodo"
    pveum aclmod "/sdn/zones"                   --user "${USUARIO}@pve" --role ProfesorRole     2>/dev/null || err "Error ACL SDN"
    ok "Pool y permisos asignados"

    echo ""
    echo "  =============================================="
    echo "   PROFESOR CREADO CORRECTAMENTE"
    echo "  =============================================="
    echo "   Usuario Proxmox : ${USUARIO}@pve"
    echo "   Pool            : pool_${USUARIO}"
    echo "   Storage         : nas-prof-${USUARIO}"
    echo "   Carpeta NAS     : /profesores/${USUARIO}"
    echo "   Windows centro  : \\\\${NAS_IP}\\${USUARIO}"
    echo "   Windows casa    : \\\\${NAS_IP_ZEROTIER}\\${USUARIO}"
    echo "  =============================================="
    echo ""
}

# ----------------------------------------------------------------
# Gestionar VMs del pool antes de eliminar
# Espera a que cada VM esté completamente destruida antes de continuar
# para evitar errores al eliminar el storage con discos aún en uso
# ----------------------------------------------------------------
gestionar_vms_pool() {
    local VMS
    VMS=$(pvesh get /pools/pool_${USUARIO} --output-format json 2>/dev/null | \
        python3 -c "import sys,json; [print(m['vmid']) for m in json.load(sys.stdin).get('members',[]) if m.get('type')=='qemu']" 2>/dev/null)
    [ -z "$VMS" ] && return
    echo "  VMs en el pool pool_${USUARIO}:"
    for VMID in $VMS; do
        echo "   - VM $VMID ($(qm config $VMID 2>/dev/null | grep "^name:" | awk '{print $2}'))"
    done
    echo "   1. Eliminar VMs permanentemente"
    echo "   2. Mover al nodo principal (transferir a root)"
    read -p "  Opcion [1/2]: " OPCION_VMS; echo ""
    case "$OPCION_VMS" in
        1) for VMID in $VMS; do
               qm status $VMID 2>/dev/null | grep -q "running" && qm stop $VMID 2>/dev/null
               qm destroy $VMID --purge 1 2>/dev/null \
                   && echo "   - VM $VMID eliminada" \
                   || echo "   AVISO: No se pudo eliminar VM $VMID"
               local INTENTOS=0
               until ! qm config $VMID 2>/dev/null | grep -q "vmid\|name"; do
                   INTENTOS=$((INTENTOS+1)); [ $INTENTOS -ge 10 ] && break
                   sleep 2
               done
           done ;;
        2) for VMID in $VMS; do
               pvesh set /pools/pool_${USUARIO} --vms $VMID --delete 1 2>/dev/null \
                   && echo "   - VM $VMID transferida a root" \
                   || echo "   AVISO: No se pudo transferir VM $VMID"
           done ;;
        *) echo "  Opcion invalida. VMs sin cambios." ;;
    esac
}
# ----------------------------------------------------------------
# Eliminar profesor
# ----------------------------------------------------------------
eliminar_profesor() {
    echo ""; echo "  === Eliminar profesor ==="; echo ""

    read -p "  Usuario a eliminar: " USUARIO
    USUARIO=$(echo "$USUARIO" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
    [ -z "$USUARIO" ] && { echo "  ERROR: Nombre vacio"; exit 1; }

    auth_nas

    echo "  Comprobando elementos existentes..."
    local EXISTE_PVE_USER=false EXISTE_PVE_POOL=false EXISTE_PVE_STORAGE=false
    local EXISTE_NAS_USER=false EXISTE_NAS_SHARE=false EXISTE_NAS_DIR=false

    pveum user list | grep -q "${USUARIO}@pve"     && EXISTE_PVE_USER=true
    pveum pool list | grep -q "pool_${USUARIO}"    && EXISTE_PVE_POOL=true
    pvesm status   | grep -q "nas-prof-${USUARIO}" && EXISTE_PVE_STORAGE=true
    [ "$(nas "qcli_users -l 2>/dev/null | grep -c '${USUARIO}'" | tr -d '\n\r')" -gt 0 ] 2>/dev/null \
        && EXISTE_NAS_USER=true
    [ "$(nas "/sbin/qcli_sharedfolder -l 2>/dev/null | grep -c '[[:space:]]${USUARIO}[[:space:]]*$'" | tr -d '\n\r')" -gt 0 ] 2>/dev/null \
        && EXISTE_NAS_SHARE=true
    [ "$(nas "[ -d '${NAS_BASE}/${USUARIO}' ] && echo si || echo no")" = "si" ] \
        && EXISTE_NAS_DIR=true

    echo ""
    printf "  %-38s : %s\n" "Usuario Proxmox (${USUARIO}@pve)"        "$EXISTE_PVE_USER"
    printf "  %-38s : %s\n" "Pool (pool_${USUARIO})"                  "$EXISTE_PVE_POOL"
    printf "  %-38s : %s\n" "Storage (nas-prof-${USUARIO})"           "$EXISTE_PVE_STORAGE"
    printf "  %-38s : %s\n" "Usuario NAS"                             "$EXISTE_NAS_USER"
    printf "  %-38s : %s\n" "Share Samba (\\\\${NAS_IP}\\${USUARIO})" "$EXISTE_NAS_SHARE"
    printf "  %-38s : %s\n" "Carpeta NAS (/profesores/${USUARIO})"    "$EXISTE_NAS_DIR"
    echo ""

    ! $EXISTE_PVE_USER && ! $EXISTE_PVE_POOL && ! $EXISTE_PVE_STORAGE && \
    ! $EXISTE_NAS_USER && ! $EXISTE_NAS_SHARE && ! $EXISTE_NAS_DIR \
        && { echo "  Nada que eliminar."; exit 0; }

    $EXISTE_PVE_POOL && gestionar_vms_pool

    local CONSERVAR_CARPETA=false
    $EXISTE_NAS_DIR && {
        read -p "  Conservar carpeta del NAS? [s/N]: " CONSERVAR
        [[ "$CONSERVAR" == "s" || "$CONSERVAR" == "S" ]] && CONSERVAR_CARPETA=true
        echo ""
    }

    echo "  Se eliminaran:"
    $EXISTE_PVE_USER    && echo "   - Usuario Proxmox: ${USUARIO}@pve"
    $EXISTE_PVE_POOL    && echo "   - Pool: pool_${USUARIO}"
    $EXISTE_PVE_STORAGE && echo "   - Storage: nas-prof-${USUARIO}"
    $EXISTE_NAS_USER    && echo "   - Usuario NAS: ${USUARIO}"
    $EXISTE_NAS_SHARE   && echo "   - Share Samba: \\\\${NAS_IP}\\${USUARIO}"
    $EXISTE_NAS_DIR     && { $CONSERVAR_CARPETA \
        && echo "   - Carpeta NAS: SE CONSERVA" \
        || echo "   - Carpeta NAS: /profesores/${USUARIO}"; }
    echo ""
    read -p "  Confirmar? [s/N]: " CONFIRMAR
    [[ "$CONFIRMAR" != "s" && "$CONFIRMAR" != "S" ]] && { echo "  Cancelado."; exit 0; }
    echo ""

    $EXISTE_PVE_STORAGE && pvesm remove "nas-prof-${USUARIO}" 2>/dev/null  && ok "Storage eliminado"         || true
    # Limpiar directorio aunque pvesm remove haya fallado
    umount -l "/mnt/pve/nas-prof-${USUARIO}" 2>/dev/null
    rm -rf "/mnt/pve/nas-prof-${USUARIO}" 2>/dev/null
    $EXISTE_PVE_POOL    && pveum pool delete "pool_${USUARIO}" 2>/dev/null  && ok "Pool eliminado"            || true
    $EXISTE_PVE_USER    && pveum user delete "${USUARIO}@pve" 2>/dev/null   && ok "Usuario Proxmox eliminado" || true
    $EXISTE_NAS_SHARE   && nas "/sbin/qcli_sharedfolder -D sharename='${USUARIO}'" && ok "Share Samba eliminado" || true
    nas "sed -i '/${USUARIO}/d' /etc/exports && exportfs -ra" 2>/dev/null   && ok "Export NFS eliminado"
    # Limpiar directorio NFSv4 huérfano si quedó tras eliminar el share
    nas "rm -rf '/share/NFSv=4/${USUARIO}'" 2>/dev/null
    $EXISTE_NAS_USER    && nas "qcli_users -d username='${USUARIO}' sid=${SID}" && ok "Usuario NAS eliminado" || true
    if $EXISTE_NAS_DIR; then
        $CONSERVAR_CARPETA \
            && ok "Carpeta /profesores/${USUARIO} conservada" \
            || { nas "rm -rf '${NAS_BASE}/${USUARIO}'" && ok "Carpeta eliminada" || true; }
    fi

    echo ""
    echo "  =============================================="
    echo "   PROFESOR ELIMINADO: ${USUARIO}"
    $CONSERVAR_CARPETA && echo "   Carpeta NAS conservada"
    echo "  =============================================="
    echo ""
}

# ----------------------------------------------------------------
# Menú principal
# ----------------------------------------------------------------
clear
echo ""
echo "  =============================================="
echo "   Gestion de Profesores — Proxmox + NAS"
echo "  =============================================="
echo ""
echo "   1. Crear profesor"
echo "   2. Eliminar profesor"
echo ""
read -p "   Opcion [1/2]: " OPCION; echo ""

case "$OPCION" in
    1) verificar_rol; echo ""; crear_profesor ;;
    2) eliminar_profesor ;;
    *) echo "  Opcion invalida."; exit 1 ;;
esac
