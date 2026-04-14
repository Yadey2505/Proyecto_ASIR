# Infraestructura Educativa con Proxmox + QNAP + FOG + ZeroTier

Sistema de infraestructura para entornos educativos que combina virtualización, almacenamiento centralizado, despliegue de imágenes y acceso remoto seguro.

---

## 🏗️ Arquitectura del proyecto

```
ZeroTier (acceso remoto)
        │
        ▼
┌───────────────────────────────────────┐
│           PROXMOX 9                   │
│  Hypervisor central                   │
│                                       │
│  VM: FOG (disco local) ────────────► Aulas (captura/despliegue Windows)
│                                       │
│  Pool profesor_A → nas-prof-A (NAS)   │
│  Pool profesor_B → nas-prof-B (NAS)   │
│  Pool profesor_N → nas-prof-N (NAS)   │
│              │                        │
│     VMs corren en Proxmox             │
│     Discos almacenados en NAS via NFS │
│              ▼                        │
└──────────────┼────────────────────────┘
               │ NFS
               ▼
┌──────────────────────────┐
│     NAS QNAP TS-431P     │
│     10 TB RAID5          │
│                          │
│  /profesores/            │
│    ├── juan/  (privado)  │
│    └── maria/ (privado)  │
│  /recursos/  (público)   │
│    └── template/iso/     │
│  /backups/   (admin)     │
│  /fog/                   │
│    └── imagenes/         │
└──────────────────────────┘
```

---

## 🖥️ Componentes

### Proxmox 9
- Hypervisor principal — las VMs **funcionan** aquí, sus discos se almacenan en el NAS
- Gestión de pools privados por profesor
- Disco de FOG en local (local-lvm) para mejor rendimiento de captura/despliegue
- Acceso via navegador web (noVNC)

### NAS QNAP TS-431P (QTS 4.3.4)
- 4 discos en RAID5 → 10.63 TB útiles
- Samba para acceso desde Windows (share privado por profesor)
- NFS para montaje en Proxmox (share individual por profesor)
- ZeroTier instalado para acceso remoto
- Imágenes FOG almacenadas en `/fog/imagenes/`

### FOG Project
- Captura y despliegue de imágenes Windows en aulas
- VM con disco en `local-lvm` de Proxmox
- Imágenes almacenadas en `/fog/imagenes/` del NAS

### ZeroTier
- VPN para acceso remoto desde casa
- Profesores acceden a Proxmox y NAS como si estuvieran en el centro

---

## 📋 IPs del proyecto

| Dispositivo | IP Actual (temporal) | IP Definitiva (día 18) | IP ZeroTier |
|---|---|---|---|
| Proxmox | 10.0.20.219 | 192.168.1.100 | 10.230.74.86 |
| NAS QNAP | 10.0.86.82 | 192.168.1.200 | 10.230.74.51 |

> ⚠️ Actualizar `NAS_IP` y `PROXMOX_IP` en el script el día 18.

---

## 📁 Estructura del NAS

| Carpeta | Propósito | Acceso |
|---|---|---|
| `/profesores/USUARIO/` | Datos y VMs privados del profesor | Solo el profesor + admin |
| `/recursos/` | Recursos públicos | Lectura y escritura todos (usuario: everyone) |
| `/recursos/template/iso/` | ISOs para crear VMs en Proxmox | Via NFS desde Proxmox |
| `/backups/` | Backups automáticos de Proxmox | Solo admin |
| `/fog/imagenes/` | Imágenes Windows capturadas por FOG | Solo FOG + admin |

---

## 👤 Gestión de profesores

Cada profesor tiene:
- **Usuario en QNAP** con acceso Samba a su carpeta privada
- **Share Samba oculto** en el NAS: `\\NAS\nombreprofesor`
- **Carpeta física** en el NAS: `/profesores/nombreprofesor`
- **Usuario en Proxmox** (`nombre@pve`)
- **Pool privado** en Proxmox (`pool_nombre`)
- **Storage NFS privado** en Proxmox (`nas-prof-nombre`)

### Acceso desde Windows

```
Carpeta privada (centro):    \\192.168.1.200\nombreprofesor
Carpeta privada (casa):      \\10.230.74.51\nombreprofesor
Recursos públicos (centro):  \\192.168.1.200\recursos  (usuario: everyone, sin contraseña)
Recursos públicos (casa):    \\10.230.74.51\recursos   (usuario: everyone, sin contraseña)
```

> ⚠️ Windows no permite sesiones simultáneas con diferentes usuarios al mismo servidor.
> Si hay conflicto: `net use * /delete /yes` en CMD y reconectar.
>
> ⚠️ En Windows modernos puede ser necesario activar el acceso de invitados:
> `reg add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" /v AllowInsecureGuestAuth /t REG_DWORD /d 1 /f`

### Acceso a Proxmox

```
Centro: https://192.168.1.100:8006
Casa:   https://10.230.74.86:8006
```

### Visibilidad en Proxmox por rol

| Usuario | Ve |
|---|---|
| `root@pam` | Todo |
| `USUARIO@pve` | Solo su pool, su storage privado y nas-recursos |

---

## 🔐 Privacidad y seguridad

- Cada profesor solo ve su pool en Proxmox
- Las carpetas del NAS tienen `chmod 700` (solo el propietario accede)
- Los shares Samba son ocultos (`hidden=1`, `browsable=no`)
- Acceso NFS restringido a la IP local de Proxmox
- ZeroTier gestiona el acceso remoto seguro

---

## 💽 Almacenamiento Proxmox

```
VG: pve (4TB disco físico)
├── root:          96GB  → Sistema Proxmox
├── swap:           8GB  → Memoria swap
├── data (thin):  200GB  → Thin pool — solo para VM FOG
│   └── vm-102:   62GB  → Disco VM FOG
└── Libre:        ~3.4TB → Disponible para crecer
```

Las VMs de profesores almacenan sus discos en el NAS via NFS, no en el thin pool local.

---

## 🔧 Script de gestión: `gestionar_profesor.sh`

### Qué hace al crear un profesor (8 pasos)

```
1. Crea usuario nativo en QNAP con Samba
2. Añade al grupo "profesores"
3. Crea carpeta privada /profesores/USUARIO (chmod 700)
4. Crea share Samba oculto. Espera a que aparezca en smb.conf
   (asíncrono en QNAP) antes de insertar admin users = USUARIO
5. Ejecuta qcli_sharedfolder -N (crea /share/NFSv=4/USUARIO y escribe
   en /etc/exports), espera, reescribe líneas limpias sin wildcard *
   ni duplicados y recarga con exportfs -ra
6. Limpia directorio huérfano si existe, espera export en showmount,
   monta storage NFS privado en Proxmox (sin --options vers=3)
7. Crea usuario USUARIO@pve en Proxmox
8. Crea pool y asigna todos los permisos necesarios
```

### Qué hace al eliminar un profesor

```
- Gestiona VMs del pool (eliminar o mover al admin)
  Al eliminar: espera a que cada VM esté completamente destruida
  antes de continuar (evita errores con discos en uso)
- Elimina storage NFS + limpia directorio /mnt/pve/nas-prof-USUARIO
- Elimina pool y usuario de Proxmox
- Elimina share Samba del NAS
- Limpia líneas del usuario en /etc/exports y recarga
- Limpia /share/NFSv=4/USUARIO huérfano
- Elimina usuario del NAS
- Elimina carpeta del NAS (pregunta si conservarla)
```

### Configuración del script

```bash
NAS_IP="10.0.86.82"              # IP local del NAS → cambiar a 192.168.1.200 el día 18
NAS_IP_ZEROTIER="10.230.74.51"   # IP ZeroTier del NAS
PROXMOX_IP="10.0.20.219"         # IP local de Proxmox → cambiar a 192.168.1.100 el día 18
PROXMOX_NODE="server"            # Nombre del nodo Proxmox
NAS_VOLUME_ID="1"                # VolumeID del RAID5 en QNAP
```

---

## 🗓️ Pendiente

- [ ] Actualizar IPs en el script el día 18
- [ ] Ir al centro y capturar imagen Windows con FOG
- [ ] Eliminar VM SRV-FILES (ID 101, apagada)
- [ ] Probar acceso Samba desde PCs del centro en red local

---

## 📝 Notas técnicas importantes

### NFS en QNAP QTS 4.3.4
- `qcli_sharedfolder -N` escribe en `/etc/exports` Y crea `/share/NFSv=4/USUARIO` — sin este directorio `exportfs -ra` falla
- El QNAP añade automáticamente `*(ro,...)` y entradas duplicadas en `/etc/exports`
- Solución: reescribir las líneas con `sed` tras el `-N` y recargar con `exportfs -ra`
- `qcli_sharedfolder -T` es innecesario — `-N` ya añade la IP automáticamente
- `qcli_sharedfolder -R` NO funciona en QTS 4.3.4
- Los storages `nas-prof-USUARIO` NO deben usar `--options vers=3` — causa `inactive` en la GUI

### Samba en QNAP
- Requiere `admin users = USUARIO` en smb.conf para autenticación correcta
- El QNAP escribe smb.conf de forma asíncrona — hay que esperar a que el share aparezca antes de modificarlo
- NO usar `killall smbd` manualmente (corrompe la configuración)
- El sid de autenticación caduca: renovar con `qcli -l user=admin pw=PASS saveauthsid=yes`

### Storages en Proxmox
- Los directorios `/mnt/pve/nas-prof-USUARIO` pueden quedar huérfanos si el script falla — se limpian automáticamente en rollback y al eliminar
- Para limpiar manualmente: `umount -l /mnt/pve/nas-prof-X && rm -rf /mnt/pve/nas-prof-X`
