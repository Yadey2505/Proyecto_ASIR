# Infraestructura de almacenamiento y servicios para centro educativo

Este proyecto documenta el diseño e implementación de una infraestructura de red y almacenamiento orientada a un entorno educativo, con separación clara de roles entre profesorado y alumnado, acceso remoto seguro y administración centralizada.

---

## 🎯 Objetivo del proyecto

El objetivo principal es proporcionar un sistema que permita:

- Al **profesorado** disponer de un espacio privado y persistente para almacenar y gestionar archivos.
- Al **alumnado** acceder a recursos comunes sin necesidad de autenticación.
- Al **administrador** gestionar usuarios, permisos y accesos de forma segura y automatizada.
- Permitir **acceso remoto** a los servicios sin exponerlos directamente a Internet.

---

## 🏗️ Arquitectura general

La infraestructura se apoya en las siguientes tecnologías:

- **Hipervisor:** Proxmox VE
- **Servidor de archivos:** srv-files (Linux)
- **Almacenamiento:** NAS montado mediante NFS
- **Compartición de archivos:** Samba
- **Acceso remoto:** ZeroTier
- **Despliegue y clonación de equipos:** FOG Project

La arquitectura está diseñada para minimizar la superficie de ataque y facilitar el mantenimiento a largo plazo.

---

## 🌐 Redes utilizadas

- **Red LAN:** `192.168.1.0/24`
- **Red virtual privada:** ZeroTier (`10.x.x.x`)

El acceso remoto se realiza exclusivamente a través de ZeroTier.

---

## 📂 Estructura del repositorio
docs/
scripts/

- **docs/** → Documentación técnica detallada  
- **scripts/** → Scripts de automatización  

---

## 📁 Estructura del almacenamiento

El NAS se monta en el servidor de archivos y se organiza de la siguiente forma:
```
/mnt/nas
├── profesorado/
│ ├── usuario1/
│ └── usuario2/
└── alumnado/
```

### Profesorado
- Carpeta privada por usuario
- Acceso autenticado mediante Samba
- Permisos de lectura y escritura

### Alumnado
- Carpeta común
- Acceso como invitado (guest)
- Sin usuarios locales ni Samba
- Acceso limitado a recursos públicos

---

## 👥 Gestión de usuarios

- Cada profesor dispone de:
  - Usuario Linux
  - Usuario Samba
  - Carpeta privada en el NAS
- El alumnado **no tiene usuarios creados** en el sistema.
- La creación de usuarios del profesorado se automatiza mediante script.

---

## 🚀 Automatización

El proyecto incluye un script interactivo para la creación segura de usuarios del profesorado:
scripts/crear_profesor.sh

El script:
- Comprueba si el usuario ya existe
- Verifica carpetas locales y en el NAS
- Crea usuarios Linux y Samba si es necesario
- Aplica permisos correctos
- Muestra el estado final de la configuración

---

## 💻 Despliegue y clonación de equipos (FOG)

El sistema de despliegue de equipos del aula se basa en **FOG Project**, una plataforma de clonación y administración de equipos mediante red.

FOG permite capturar imágenes completas de un sistema operativo y desplegarlas posteriormente en múltiples equipos de forma automatizada a través de la red.

---

### 🎯 Objetivo en la infraestructura

El uso de FOG permite:

- **Capturar una imagen base** de un equipo Windows configurado para el aula.
- **Desplegar rápidamente** esa imagen en todos los equipos de los alumnos.
- Mantener **todos los equipos con la misma configuración** de software.
- Reducir el tiempo necesario para **reinstalaciones o recuperación del sistema**.
- Facilitar la **gestión centralizada de los equipos del aula**.

---

### 🧩 Funcionamiento general

El proceso de trabajo con FOG sigue tres fases principales:

1. **Registro del equipo**
   - El equipo cliente arranca por red mediante **PXE**.
   - Se registra automáticamente en el servidor FOG.

2. **Captura de imagen**
   - Se prepara un equipo maestro con:
     - Windows instalado
     - Software educativo necesario
     - Configuración del sistema del aula
   - El equipo arranca por red y FOG **captura la imagen del disco**.
   - La imagen queda almacenada en el servidor FOG.

3. **Despliegue de la imagen**
   - Los equipos del aula arrancan mediante **PXE**.
   - El servidor FOG despliega la imagen almacenada.
   - Todos los equipos reciben una **instalación idéntica**.

---


Este modelo permite reinstalar **todos los equipos del aula en pocos minutos**, garantizando que cada equipo tenga exactamente la misma configuración.

---

### 🌐 Integración con la red del proyecto

FOG se integra dentro de la infraestructura de la siguiente manera:

- **Servidor:** en la red LAN `192.168.1.139/24`
- **Clientes:** equipos Windows del aula
- **Arranque de red:** mediante **PXE**
- **Gestión:** interfaz web del servidor FOG

El tráfico de clonación se mantiene **dentro de la red local**, evitando saturar otros segmentos de red y mejorando la velocidad de despliegue.

---

### 📦 Ventajas en el entorno educativo

- Instalación masiva de sistemas en **pocos minutos**
- Restauración rápida tras errores del alumnado
- **Homogeneidad** en todos los equipos del aula
- Reducción del trabajo de mantenimiento
- Gestión centralizada desde un único servidor

## 🔐 Seguridad

- No se exponen servicios directamente a Internet
- Acceso remoto exclusivamente mediante ZeroTier
- Separación estricta entre datos públicos y privados
- Uso de permisos mínimos necesarios
- Sin cuentas de alumnado en el sistema

---

## 📚 Documentación

Toda la documentación técnica se encuentra en la carpeta `docs/`.

---

## 🛠️ Requisitos

- Proxmox VE
- Sistema Linux (Ubuntu Server)
- NAS compatible con NFS
- Cliente ZeroTier
- Clientes Windows/Linux para acceso Samba

---

## 📌 Notas finales

Este proyecto está diseñado para ser:

- Reproducible
- Seguro
- Escalable
- Fácil de mantener
- Correctamente documentado para uso futuro
