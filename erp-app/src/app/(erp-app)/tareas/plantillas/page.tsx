import { notFound } from "next/navigation";
import { puedeAdministrar, puedePedir, puedeVerEquipo, puedeVerPlantillas } from "@/modules/tareas/permissions";
import { getAsignables, getContexto, getEntesSobre, getPlantillas } from "@/modules/tareas/queries";
import { PlantillasView } from "@/modules/tareas/components/PlantillasView";

export default async function PlantillasPage(props: PageProps<"/tareas/plantillas">) {
  if (!(await puedeVerPlantillas())) notFound();
  const { ver } = await props.searchParams;

  const [plantillas, entes, contexto, asignables, admin, pedir, delegador] = await Promise.all([
    getPlantillas(),
    getEntesSobre(),
    getContexto(),
    getAsignables(),
    puedeAdministrar(),
    puedePedir(),
    puedeVerEquipo(),
  ]);

  return (
    <PlantillasView
      plantillas={plantillas}
      entes={entes}
      ver={ver === "catalogo" || (ver === "otras" && admin) ? ver : "mias"}
      ctx={{ ...contexto, asignables, admin, pedir, delegador }}
    />
  );
}
