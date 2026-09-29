import { notFound } from "next/navigation";
import { idSchema } from "@/lib/validacion";
import { puedeAdministrar, puedePedir, puedeVerEquipo, puedeVerPlantillas, puedeVerTareas } from "@/modules/tareas/permissions";
import { getAsignables, getContexto, getHilo, getPlantillas } from "@/modules/tareas/queries";
import { HiloView } from "@/modules/tareas/components/HiloView";
import { accionDe } from "../../fichas";
import { pestanasDePaso } from "../pestanas";

export default async function HiloPage(props: PageProps<"/tareas/[id]">) {
  const { id } = await props.params;
  const params = await props.searchParams;
  const { paso } = params;
  if (!(await puedeVerTareas()) || !idSchema.safeParse(id).success) notFound();

  const [datos, contexto, asignables, admin, pedir, delegador, plantillas] = await Promise.all([
    getHilo(id),
    getContexto(),
    getAsignables(),
    puedeAdministrar(),
    puedePedir(),
    puedeVerEquipo(),
    puedeVerPlantillas().then((ver) => (ver ? getPlantillas() : [])),
  ]);
  if (!datos) notFound();
  const abierto = datos.pasos.find((p) => p.id === paso);
  const pestanas = abierto ? await pestanasDePaso(datos.hilo, datos.sobre, abierto.descripcion, datos.enlaces, accionDe(params)) : [];

  return (
    <HiloView
      {...datos}
      pasoAbierto={abierto?.id ?? null}
      pestanas={pestanas}
      plantillas={plantillas.filter((p) => p.activo && p.dueno_id === contexto.yo)}
      ctx={{ ...contexto, asignables, admin, pedir, delegador }}
    />
  );
}
