"""Whether the bitmap behind a material can satisfy the shader it asks for.

A .jms names one shader per material, and tool.exe looks each name up by NAME,
wherever the tag sits - it never asks what that shader points at. A shader whose
base map is blank therefore compiles, bakes and draws white in game, and
recompiling the model changes nothing. The white face is that failure exactly:
the costume's face materials are laid out for the avatar's face sheet, the sheet
was not written for that export, so the item's own atlas pads the face blank -
every face lands on one colour, and the game draws a white, eyeless mask under
the helmet.

So the run asks this question before it writes a model, and refuses when the
answer is "that shader cannot be drawn with what I have". The bitmap itself is
read by the caller (it needs Blender for that); the decision lives here so it can
be tested without it.
"""


def gap(name, has_bitmap, colours_seen, least=2):
    """Why this material's shader cannot be drawn, or None when it can.

    ``has_bitmap`` is whether the material has an image node holding an image,
    and ``colours_seen`` how many distinct colours that image has under the
    coordinates this material's own faces read.

    A body sheet of a single flat colour is left alone: that is the item's own
    paint, and a flat colour drawn as itself is not a white face. A *face*
    material on one colour is the white mask, and is refused.
    """
    if not has_bitmap:
        return ("no bitmap bound - the material has no image, so its base map "
                "is whatever the shader tag happens to hold")
    if colours_seen <= 0:
        return "the bitmap has no pixels where this material reads"
    if colours_seen < least and "face" in (name or "").lower():
        return ("one flat colour under every face - the avatar's face sheet is "
                "missing, so the item's own map pads the face blank and the game "
                "draws white")
    return None


def refusal(gaps, stem=""):
    """The line a refused model is reported with."""
    listed = "; ".join("%s: %s" % pair for pair in gaps)
    return ("refused to write %s's model - %d material(s) name a shader that no "
            "bitmap here can draw (%s). tool.exe would bake each of them and that "
            "surface would draw white in game, so no .jms is written"
            % (stem or "the model", len(gaps), listed))
