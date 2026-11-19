// Dirty Double Jump - poison syringe body: green poison fluid swirling under the syringe glass
models/multiplayer/syringe/poison
{
	cull disable
	{
		map gfx/misc/poisonfluid.tga
		rgbGen lightingDiffuse
		tcMod scale 2 2
		tcMod scroll 0 -0.2
		tcMod turb 0 0.3 0 0.1
	}
	{
		map gfx/misc/poisonfluid.tga
		blendFunc blend
		rgbGen lightingDiffuse
		tcMod scale 1.5 2.5
		tcMod scroll 0 -0.25
		tcMod turb 0 0.2 0 0.15
	}
	{
		map models/multiplayer/syringe/syringepoison.tga
		blendFunc blend
		rgbGen lightingDiffuse
	}
	{
		map models/multiplayer/syringe/syringe_reflections.tga
		blendFunc blend
		rgbGen lightingDiffuse
	}
}

// Dirty Double Jump - icon drawn over poisoned players
sprites/poisoned
{
	nocompress
	nopicmip
	{
		map sprites/poisoned.tga
		blendFunc blend
		rgbGen vertex
	}
}
