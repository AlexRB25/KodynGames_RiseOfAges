# Arte de Rise of Ages: dónde va cada cosa

Pon los PNG en estas carpetas con estos nombres y el juego los usa solos. Si falta una imagen, el juego usa la que tenga más cerca (otro nivel) o lo dibujado por código. Un archivo que falta nunca rompe el juego.

```
assets/
├── ui/
│   ├── logo.png                 logo "Rise of Ages" (menú y landing)
│   ├── fondo.jpg                fondo del menú (1920×1080 o más)
│   ├── portada.jpg              arte grande (portada de la landing / tiendas)
│   └── iconos/                  barra de arriba
│       ├── alimento.png  madera.png  oro.png  piedra.png  poblacion.png
│
├── eras/                        insignia del centro de la pantalla (nivel/era 1-5)
│   └── nivel1.png … nivel5.png  I Aldea Primitiva · II Era Tribal · III Era de Piedra
│                                IV Era de los Metales · V Era Imperial
│
└── civs/<civilizacion>/         mexica, maya, purepecha, zapoteca, tolteca
    ├── eras/nivel1..5.png       (opcional) insignias propias de esa civilización
    ├── unidades/<unidad>/nivel1..5.png
    │      aldeano, guerrero, lancero, arquero, jinete, barco_pesca, barco_guerra
    └── edificios/<edificio>/nivel1..5.png
           centro, casa, maderero, minero, molino, granja, cuartel, arqueria,
           establo, torre, muralla, puerta, mercado, templo, castillo, muelle
```

## Ejemplos

- Aldeano maya de la era 3: `civs/maya/unidades/aldeano/nivel3.png`
- Arquero mexica de la era 4: `civs/mexica/unidades/arquero/nivel4.png`
- Casa purépecha de la era 2: `civs/purepecha/edificios/casa/nivel2.png`
- Centro tolteca de la era 5: `civs/tolteca/edificios/centro/nivel5.png`

Una civilización nueva (españoles, incas, orcos…) lleva su propia carpeta en `civs/` con el mismo id que su archivo en `data/civs/`. Ya hay carpetas de `orco` y `humano` con el arte que mandaste; se usarán cuando existan esas civilizaciones.

## Cómo deben ser las imágenes

- **PNG**, cuadradas, de 256×256 a 512×512, con el personaje o edificio centrado. Para los iconos de arriba, mejor con fondo transparente.
- **Una imagen por nivel**, sin texto ni etiquetas encima. Las hojas tipo "Nivel 1 … Nivel 5" están bien como referencia, pero yo tengo que recortarlas. Ya recorté las que mandaste.
- **Insignias de era**: horizontales (unos 3:1) y con fondo transparente, como las que mandaste.

## Dónde se ven en el juego

- **Iconos**: en la barra de arriba (alimento, madera, oro, piedra, población).
- **Insignia de la era**: arriba al centro, con "Nivel N". Cambia sola al subir de era.
- **Retrato de unidad o edificio**: en el panel de abajo, al seleccionarlo, según su civilización y su era.
- **Logo y fondo**: en el menú principal.

## Modelos 3D (Meshy)

Los edificios del mapa pueden usar un modelo 3D en vez de la figura hecha por código:

```
assets/modelos/<civilizacion>/<edificio>/nivelN.glb     ej. assets/modelos/maya/centro/nivel5.glb
```

- El juego lo ajusta solo al tamaño en casillas del edificio y le pone una franja del color del jugador en la base.
- Si falta un nivel, usa el más cercano; si no hay modelo, usa la figura de siempre.
- **Para generarlos con la API de Meshy:**
  `python tools/meshy_generar.py imagen.png assets/modelos/maya/casa/nivel1.glb`
  Usa Smart Topology, unos 4,000 triángulos con textura, 15 créditos y menos de un minuto. La clave sale de la variable MESHY_API_KEY.
- **Después de agregar modelos:** primero `godot --headless --path . --import`, luego `python tools/ajustar_texturas_modelos.py` y otra vez el import. Así las texturas quedan en 512 px: cada edificio pesa unos 260 KB en la web en vez de 6 MB.
- **La imagen para Meshy:** un solo edificio, vista 3/4 desde arriba, completo y sin cortar, con fondo liso o transparente, sin pasto alrededor ni texto.

Los personajes (aldeanos, guerreros) todavía son figuras hechas por código. Con Meshy se pueden hacer con esqueleto y animaciones, pero primero hay que probar el rendimiento con muchos en pantalla.

## Si no quieres acomodarlo tú

Déjalo todo suelto en una carpeta (como `Downloads/Rise of Ages`) y dime. Yo lo recorto y lo acomodo aquí. Las hojas originales que mandaste quedaron en `arte_referencias/`.
