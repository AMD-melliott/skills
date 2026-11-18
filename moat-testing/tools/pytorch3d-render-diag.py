# Per camera x shader for test_simple_sphere(elevated_camera=True): pixels over the test's atol (0.05)
# vs the reference PNG, for the GPU render and a CPU render of the same scene.
import sys, torch
sys.path.insert(0, ".")
from tests.common_testing import load_rgb_image
from tests.test_render_meshes import DATA_DIR
from pytorch3d.renderer import (FoVPerspectiveCameras, FoVOrthographicCameras, PerspectiveCameras, OrthographicCameras,
    look_at_view_transform, Materials, PointLights, RasterizationSettings, BlendParams, MeshRenderer, MeshRasterizer,
    HardPhongShader, HardGouraudShader, HardFlatShader)
from pytorch3d.renderer.fisheyecameras import FishEyeCameras
from pytorch3d.utils.ico_sphere import ico_sphere
print("torch", torch.__version__, "hip", torch.version.hip)
R, T = look_at_view_transform(dist=2.7, elev=45.0, azim=45.0)
def render(dev, cam_type, shader_cls):
    from pytorch3d.renderer.mesh.textures import TexturesVertex
    mesh = ico_sphere(5, dev); v = mesh.verts_padded(); mesh.textures = TexturesVertex(verts_features=torch.ones_like(v, device=dev))
    kw = {}
    if cam_type == FishEyeCameras:
        kw = dict(use_tangential=True, use_radial=True, use_thin_prism=True, world_coordinates=True,
                  radial_params=torch.tensor([[-1, -2, -3, 0, 0, 1]], dtype=torch.float32),
                  tangential_params=torch.tensor([[0.7002747019, -0.4005228974]], dtype=torch.float32),
                  thin_prism_params=torch.tensor([[-1.000134884, -1.000084822, -1.0009420014, -1.0001276838]], dtype=torch.float32))
    cams = cam_type(device=dev, R=R, T=T, **kw)
    lights = PointLights(device=dev); lights.location = torch.tensor([0.0, 0.0, 2.0], device=dev)[None]
    sh = shader_cls(lights=lights, cameras=cams, materials=Materials(device=dev), blend_params=BlendParams(0.5, 1e-4, (0, 0, 0)))
    r = MeshRenderer(rasterizer=MeshRasterizer(cameras=cams, raster_settings=RasterizationSettings(image_size=512, blur_radius=0.0, faces_per_pixel=1)), shader=sh)
    return r(mesh)[0, ..., :3].squeeze().cpu()
for cam in (FoVPerspectiveCameras, FoVOrthographicCameras, PerspectiveCameras, OrthographicCameras, FishEyeCameras):
    for name, sh in (("phong", HardPhongShader), ("gouraud", HardGouraudShader), ("flat", HardFlatShader)):
        ref = load_rgb_image("test_simple_sphere_light_%s_elevated_%s.png" % (name, cam.__name__), DATA_DIR)
        g = render(torch.device("cuda:0"), cam, sh); c = render(torch.device("cpu"), cam, sh)
        bad = lambda a, b: int(((a - b).abs() > 0.05).any(-1).sum())
        print(f"{cam.__name__:24s} {name:13s} gpu-vs-ref {bad(g, ref):6d}px  cpu-vs-ref {bad(c, ref):6d}px  gpu-vs-cpu {bad(g, c):6d}px  maxdiff {float((g-ref).abs().max()):.3f}")
