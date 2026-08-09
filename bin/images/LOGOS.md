# Institution logos shipped with Marionnet

The files listed below are **not** part of Marionnet in the sense of the GNU GPL.
They are the emblems (trademarks) of the institutions that host and support the
project, and they remain the property of their respective owners.

They are reproduced here for one purpose only: crediting those institutions in the
splash screen and in the *About* dialog. They may **not** be reused, modified or
redistributed independently of Marionnet. Anyone forking or repackaging Marionnet
under another name is expected to remove them, or to obtain the agreement of the
institutions concerned.

The rest of Marionnet, including the `marionnet` figure of `splash.300x348.xpm`
(designed by Silviu Barsanu, see the *Thanks* tab of the *About* dialog), keeps its
own licensing.

## Origin of the files

Retrieved on 2026-08-09 from the public web sites of the institutions. Each file was
cut out over a transparent background and scaled; no other alteration was made.

| File | Institution | Source |
|---|---|---|
| `logo.uspn.png` | Université Sorbonne Paris Nord (USPN) | `https://pleiade.univ-paris13.fr/wp-content/uploads/logo_uspn.png` (stacked colour logotype, also served by `galilee.univ-paris13.fr`) |
| `logo.iutv.png` | IUT de Villetaneuse (USPN) | `https://iutv.univ-paris13.fr/wp-content/uploads/logotype-iutv-2023.png` (2023 logotype, header of the institute web site) |
| `logo.lipn.png` | Laboratoire d'Informatique de Paris Nord (LIPN, UMR 7030) | `https://lipn.univ-paris13.fr/assets/images/logo-lipn-bg-white.jpeg` (the version served by the laboratory web site, `LIPN_logo.webp`, is white and would be invisible here) |
| `logo.unif.png` | Université numérique Île-de-France (UNIF) | `https://unif.fr/wp-content/uploads/2025/04/logo-unif-760.png` (main colour version) |
| `logo.sponsors.png` | USPN + UNIF | built from `logo.uspn.png` and `logo.unif.png`, side by side, for the *About* dialog |

## Reference documents

- Graphic charter of USPN:
  `https://www.univ-spn.fr/wp-content/uploads/CHARTE-GRAPHIQUE-Universite-Sorbonne-Paris-Nord.pdf`
- Graphic charter of UNIF (2025):
  `https://unif.fr/wp-content/uploads/2025/05/Charte-Graphique-UNIF-2025.pdf`

## How the files were produced

```bash
# transparent background, cropped, scaled to the width used by the splash screen
box () {  # $1 = source  $2 = destination  $3 = width  $4 = cut-out tolerance (%)
  convert "$1" -fuzz "$4%" -transparent white -trim +repage -resize "${3}x" PNG32:"$2"
}
box logo_uspn.png            logo.uspn.png  94 5
box logotype-iutv-2023.png   logo.iutv.png 185 6
box logo-lipn-bg-white.jpeg  logo.lipn.png  74 12
box logo-unif-760.png        logo.unif.png 103 5
```

The widths are not arbitrary: the four logos share one row of the splash screen, and
the IUT logotype has a 6.4:1 ratio, so it needs about twice the width of the others
to stay readable. For the *About* dialog, `logo.sponsors.png` puts USPN and UNIF at a
common height of 44 px, 56 px apart.
