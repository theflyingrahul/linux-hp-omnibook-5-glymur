# util-linux patches

`0001-lscpu-add-Qualcomm-Oryon-2-part-ID.patch` (against util-linux master
`53cd4fb`, unsent; add your `Signed-off-by` before submitting) names MIDR
part `0x51/0x002` "Oryon-2", after the `qcom,oryon-2-N` CPU compatibles in
Linux `glymur.dtsi`. Tested with a native `lscpu` build on this laptop.

Why this matters: GNOME Settings shows the CPU as "(null) × 12" here. The
cause is a chain across three projects:

1. `lscpu --parse=cpu,MODELNAME` prints an empty model for unknown part `0x002`.
2. Ubuntu's libgtop patch `add-model-name-gathering-from-lscpu.patch` (2.41.3-2ubuntu1)
   stores that empty string as `model name`; it should skip empty values.
3. gnome-control-center's `get_cpu_info()` accepts the empty model;
   `prettify_info("")` returns NULL, which prints as "(null)". It should
   treat an empty model like a missing one.

Fixing 1 is enough for Ubuntu. Items 2 and 3 are defensive fixes, not yet
drafted. Fedora's libgtop does not carry the Ubuntu patch.
