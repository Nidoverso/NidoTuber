# NidoTuber

A simple PNGTuber app: show an animated avatar on your stream that opens its
mouth when you talk, blinks, moves gently and can wear accessories. Made with
[Godot Engine](https://godotengine.org).

> **About AI**
> NidoTuber was made with the help of artificial intelligence. Both the code and
> the images included in the project were created with AI tools, under the
> direction and review of Nidoverso.

---

## Contents

1. [What it does](#what-it-does)
2. [Download and start](#download-and-start)
3. [The basics](#the-basics)
4. [Your avatar](#your-avatar)
5. [Microphone](#microphone)
6. [Movement](#movement)
7. [Backgrounds](#backgrounds)
8. [Using it with OBS](#using-it-with-obs)
9. [Accessories](#accessories)
10. [Galleries and collections](#galleries-and-collections)
11. [Sharing your creations](#sharing-your-creations)
12. [Where your data is saved](#where-your-data-is-saved)
13. [Tips and common problems](#tips-and-common-problems)
14. [For developers](#for-developers)
15. [License and credits](#license-and-credits)

---

## What it does

- Your avatar uses **four images**: eyes open or closed, mouth open or closed.
- The **microphone** decides when the mouth opens.
- **Automatic blinking**, with occasional double blinks.
- Gentle **idle movement**: floating, tilting, breathing and small jumps.
- **Backgrounds**: a plain colour (green by default, ready for a chroma key) or an image.
- **Accessories**: hats, glasses, a bird flying around you, a plant on the table…
- **Galleries** to keep many avatars, backgrounds and accessories, organised in collections.
- **Import and export** everything to share it with others.
- Available in **English** and **Spanish**.

## Download and start

Download the latest version from the **Releases** page of this repository.

No installation is needed: download the file for your system and open it.

**Windows**

1. Download and open `NidoTuber.exe`.
2. The first time, Windows may show *"Windows protected your PC"*. This happens
   with programs that are not signed by a company. Click **More info** and then
   **Run anyway**.

**Linux**

1. Download `NidoTuber.x86_64`.
2. Downloaded files are not allowed to run as programs by default, so allow it
   once: right click › Properties › *Allow executing file as program*, or run
   `chmod +x NidoTuber.x86_64` in a terminal.
3. Open it.

## The basics

When NidoTuber opens you only see the avatar and the background. Everything else
is in the **options panel**:

- **Right click** anywhere, or press **Esc**, to show or hide it.
- Drag the **right edge** of the panel to make it wider or narrower.
- The panel is divided into sections you can fold and unfold by clicking their titles.

To change the language, go to **General › Language**.

Everything is saved automatically: when you close the panel and when you close the program.

## Your avatar

### The four images

Go to **Avatar › Avatar settings › Images**. Each button is one image:

| Button | Eyes | Mouth |
|---|---|---|
| **Idle** | open | closed |
| **Talking** | open | open |
| **Idle · Blink** | closed | closed |
| **Talking · Blink** | closed | open |

Click a button to choose a PNG, JPG or WebP image. A new avatar starts with
example images, so you can replace them one by one.

**Tip:** draw all four images on the same canvas size, with the character in
the same position. That way nothing jumps when the image changes.

### Size and position

In **Scale**:

- **Base size**
  - *Window height*: the avatar fills the height of the window. Good for most avatars.
  - *Original*: the image is shown at its real size in pixels.
- **Multiplier**: makes it bigger or smaller.
- **Smoothing**: turn it **off** for pixel art, so pixels stay sharp.
- **Integer scaling**: only for pixel art (with smoothing off). It makes every
  pixel exactly the same size. It cannot be used together with breathing.

In **Position** you can move the avatar horizontally and vertically, or put it
back in the middle with **Center**.

## Microphone

Go to **General › Microphone**:

- **Device**: choose your microphone.
- **Threshold**: the bar behind this slider shows your voice level. Talk
  normally and place the slider just below where your voice reaches. The bar
  turns **green** when the mouth opens.
- **Hold time**: how long the mouth stays open after you stop talking. A little
  hold time stops the mouth from flickering between words.

## Movement

All movement settings are in **Avatar settings**.

### Idle

What the avatar does all the time:

- **Motion**: the avatar slowly follows a shape. In **Shape › Figure** you can pick
  *Up and down*, *Horizontal eight*, *Vertical eight*, *Circle* or *Swing*, and
  then adjust its size with the amplitudes and its speed with the duration.
  *Reverse direction* makes it go the other way round.
- **Tilt**: rocks gently from side to side.
- **Breathing**: shrinks a tiny bit and back, as if breathing.
- **Jump**: small jumps every now and then.

Each one has an **Enabled** box, so you can use only the ones you like.

### Talking

**Jump**: a small hop every time you start talking.

### Blink

How often the avatar blinks, how long the eyes stay closed and how often it
blinks twice in a row.

## Backgrounds

Go to **Background › Background settings**:

- **Color**: the background colour. The default green is ideal for a chroma key in OBS.
- **Image**: use a picture instead. *Fit* decides how it fills the window:
  *Cover* (fills everything, may crop the edges), *Contain* (shows the whole
  picture) or *Stretch* (fills everything, may deform it).

## Using it with OBS

1. In OBS, add a **Window Capture** source and choose the NidoTuber window.
2. Right click the source › **Filters** › add **Chroma Key** (or **Color Key**)
   and choose the same green as your background.
3. Hide the options panel (right click or Esc) before going live.

You can choose the window size in **General › Window › Resolution**.

**Tip:** if you see a thin green outline around a smooth (non pixel art)
avatar, raise the *Similarity* or *Smoothness* of the chroma key filter a little.

## Accessories

Accessories are extra images you can add to your avatar or to your background:
a hat, glasses, a speech bubble, a bird, a lamp… They all work the same way;
only their settings change.

### 1. Create the accessory

Go to the **Accessories** section and press **New** to choose its image. While
**Accessory settings** is open, you see a **preview** of the accessory on top of
your avatar, so you can adjust it:

- **Image**: size, rotation, flip and smoothing. With *Base size › Avatar*, the
  accessory grows and shrinks together with your avatar.
- **Position**
  - *Anchor › Avatar*: it moves with the avatar (a hat).
  - *Anchor › Window*: it stays in place in the scene (a plant on the table).
  - *Layer*: in front of or behind the avatar.
- **States**: in which of the four avatar images it is visible. For example, a
  speech bubble only while *Talking*.
- **Follow avatar**: which avatar movements it copies. A hat copies all of them;
  a bird flying around may only copy the motion.
- **Idle**: its own movement, with the same options as the avatar.

These settings are a starting point: they are copied every time you add the
accessory somewhere.

### 2. Add it to an avatar or a background

Go to **Avatar › Avatar accessories** (or **Background › Background accessories**)
and press **Add**. From there you can:

- **Drag** the rows to change their order. The top one is drawn on top.
- Untick the **box next to each row** to hide an accessory for a while without removing it.
- Change the settings of each one separately. The same accessory can be added
  several times with different settings.
- **Reset**: go back to the accessory's settings from the Accessories section.
- **Save to accessory**: keep these settings as the accessory's new starting point.

Accessories added to a **background** belong to the scene: those *behind* stay
behind everything, and those *in front* stay in front of everything.

### Example: a bird flying around your head

1. Create the bird accessory.
2. In **Idle › Motion**, enable it and choose the **Circle** figure. Make the
   horizontal amplitude bigger than the vertical one.
3. In **Position › Layer**, choose **Alternate**: the bird goes behind the
   avatar on one side and in front on the other.
4. In **Depth**:
   - Raise **Perspective** a little, so it looks smaller when it is far away.
   - Tick **Flip on side switch**, so it always faces the way it flies.
   - If it faces the wrong way, use **Image › Flip** or **Invert side**.

## Galleries and collections

Avatars, backgrounds and accessories each have a **gallery**:

- **Click** a picture to select it.
- **Drag** pictures to change their order.
- **Search** by name. Capitals and accents do not matter.
- Buttons: *New*, *Duplicate*, *Rename*, *Delete* (sends it to the trash),
  *Import*, *Export* and *Open folder*.

**Collections** help you keep large galleries tidy, for example *Anime* and *Pixel art*:

- Press **＋** to create one.
- Move items into it by **dragging them onto its tab**, or with **Move to…**.
- **Right click** a collection tab to rename it, move it, export it or delete it.
  Deleting a collection does not delete what is inside.

## Sharing your creations

Use **Export** and **Import** in each gallery. These are the file types:

| File | Contains |
|---|---|
| `.nidotuber` | an avatar, with its accessories |
| `.nidobg` | a background, with its accessories |
| `.nidoacc` | an accessory |
| `.nidocol` | a whole collection (right click its tab › *Export collection…*) |

When you import an avatar or background, its accessories are added to your
library too. If you already have an accessory with the same image, NidoTuber
reuses it instead of making a copy.

## Where your data is saved

| System | Folder |
|---|---|
| Windows | `%APPDATA%\NidoTuber` |
| Linux | `~/.local/share/NidoTuber` |

The **Open folder** buttons in the galleries take you there. To make a backup,
copy that whole folder.

## Tips and common problems

- **The mouth does not open:** check the *Device* and lower the *Threshold* until
  the bar turns green when you talk.
- **The mouth opens with background noise:** raise the *Threshold*.
- **The mouth flickers while talking:** raise the *Hold time* a little.
- **Pixel art looks blurry:** turn off *Smoothing* (and turn on *Integer scaling*
  if you want every pixel the same size).
- **The program uses too many resources while streaming:** set
  **General › Performance › Frame rate limit** to 30 FPS.

## For developers

NidoTuber is a [Godot 4.7](https://godotengine.org/download) project written in GDScript.

1. Download the repository and open `project.godot` with Godot 4.7.
2. Press **Run** to try it.
3. To build the program, use **Project › Export** (export templates are needed:
   *Editor › Manage Export Templates*).

Good to know:

- The microphone needs **Audio › Driver › Enable Input** (already enabled in
  the project) and an audio bus called `Mic` with a capture effect (already in
  `default_bus_layout.tres`).
- The program's texts are written in English. The Spanish translation is in
  `translations/es.po`. To add a language, create another `.po` file there and
  add its code to `LANGUAGES` in `main.gd` and to `LANGUAGE_NAMES` in
  `options_panel.gd`.
- The example avatar images are in `placeholder/`.

## License and credits

All of NidoTuber, both the code and the artwork (example images and icon), is
released under the MIT License. See [`LICENSE`](LICENSE).

Made by **Nidoverso**.

### Godot Engine

NidoTuber is made with Godot Engine, available under the following license:

```
Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md).
Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Portions of this software are copyright © The FreeType Project
(www.freetype.org). All rights reserved.

Godot also includes other third-party libraries; their licenses are listed at
<https://godotengine.org/license>.
