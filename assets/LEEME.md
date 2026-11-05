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

Los personajes y edificios del **mapa 3D** todavía son figuras simples hechas por código. Para que se vean como tu arte voxel hacen falta modelos 3D (.glb, por ejemplo de MagicaVoxel o Meshy). Irían en `modelos/<civilizacion>/<unidad o edificio>/nivelN.glb` cuando los tengamos.

## Si no quieres acomodarlo tú

Déjalo todo suelto en una carpeta (como `Downloads/Rise of Ages`) y dime. Yo lo recorto y lo acomodo aquí. Las hojas originales que mandaste quedaron en `arte_referencias/`.
