// Dirty Double Jump - poison gas landmine view model (metallic env map under the poison mine texture)
models/multiplayer/landmine/plandmine
{
	{
		map textures/effects/envmap_slate_90.tga
		rgbGen lightingDiffuse
		tcGen environment
	}
	{
		map models/multiplayer/landmine/landmine2.jpg
		blendFunc GL_ONE GL_ONE_MINUS_SRC_ALPHA
		rgbGen lightingDiffuse
	}
}
