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
│              ▼ NFS                    │
└──────────────┼────────────────────────┘
               │
               ▼
┌──────────────────────────┐
│     NAS QNAP TS-431P     │
│     10 TB RAID5          │
│                          │
│  /profesores/            │
│    ├── juan/  (privado)  │
│    └── maria/ (privado)  │
│  /isos/      (público)   │
│  /backups/   (admin)     │
│  /fog/                   │
│    └── imagenes/         │
└──────────────────────────┘
```

---

## 🖥️ Componentes

### Proxmox 9
- Hypervisor principal
- Gestión de pools privados por profesor
- Almacenamiento de VMs en el NAS via NFS (storage privado por profesor)
- Disco de FOG en local (local-lvm) para mejor rendimiento
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
| `/profesores/juan/` | Datos y VMs del profesor juan | Solo juan + admin |
| `/isos/` | ISOs comunes para VMs | Lectura todos, escritura admin/profesores |
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
Carpeta privada (centro):  \\192.168.1.200\nombreprofesor
Carpeta privada (casa):    \\10.230.74.51\nombreprofesor
ISOs comunes:              \\IP_NAS\isos (usuario: everyone, sin contraseña)
```

> ⚠️ Windows no permite sesiones simultáneas con diferentes usuarios al mismo servidor.
> Si hay conflicto: `net use * /delete /yes` en CMD y reconectar.

### Acceso a Proxmox

```
Centro: https://192.168.1.100:8006
Casa:   https://10.230.74.86:8006
```

---

## 🔐 Privacidad y seguridad

- Cada profesor solo ve su pool en Proxmox
- Las carpetas del NAS tienen `chmod 700` (solo el propietario accede)
- Los shares Samba son ocultos (`hidden=1`, `browsable=no`)
- Acceso NFS restringido a la IP local de Proxmox
- ZeroTier gestiona el acceso remoto seguro

---

## 💽 Almacenamiento Proxmox (LVM)

```
VG: pve (4TB disco físico)
├── root:          96GB  → Sistema Proxmox
├── swap:           8GB  → Memoria swap
├── data (thin):  200GB  → Thin pool para VMs locales
│   └── vm-102:   62GB  → Disco VM FOG
└── Libre:        ~3.4TB → Disponible para crecer
```

> Las VMs de profesores se almacenan en el NAS, no en el thin pool local.

---

## 🔧 Script de gestión: `gestionar_profesor.sh`




### Qué hace al crear un profesor (8 pasos)

```
1. Crea usuario nativo en QNAP con Samba
2. Añade al grupo "profesores"
3. Crea carpeta privada /profesores/USUARIO (chmod 700)
4. Crea share Samba oculto (hidden=1, guest=deny)
5. Habilita NFS y da acceso rw a IP de Proxmox
6. Monta storage NFS privado en Proxmox (vers=3, images+rootdir+import)
7. Crea usuario USUARIO@pve en Proxmox
8. Crea pool y asigna todos los permisos necesarios
```

### Qué hace al eliminar un profesor

```
- Gestiona VMs del pool (eliminar o mover al admin)
- Elimina storage NFS de Proxmox
- Elimina pool de Proxmox
- Elimina usuario de Proxmox
- Elimina share Samba del NAS
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

### Nota sobre storages NFS en Proxmox
Los storages `nas-prof-USUARIO` pueden mostrar un interrogante en la GUI de Proxmox aunque estén funcionando correctamente. Es un bug visual que no afecta al funcionamiento. El storage es accesible desde Windows y Proxmox puede usarlo normalmente.
