import { notFound } from "next/navigation";
import { getUsuarioActualId } from "@/lib/usuarios";
import { puedeVerMision } from "@/modules/tareas/permissions";
import { getMision, getSobre } from "@/modules/tareas/queries";
import { MisionView } from "@/modules/tareas/components/MisionView";
import { pestanasDePaso } from "../pestanas";

// `?paso=`: el paso que se está mirando, que trae sus fichas como en el hilo (registro.md).
export default async function MisionPage(props: PageProps<"/tareas/mision">) {
  if (!(await puedeVerMision())) notFound();

  const yo = await getUsuarioActualId();
  if (!yo) notFound();
  const { paso } = await props.searchParams;
  const { pasos, cadena, enlaces } = await getMision(yo);
  const mirado = pasos.find((p) => p.id === paso);
  const pestanas = mirado
    ? await pestanasDePaso(
        { id: mirado.hilo_id, ...mirado.tareas_hilos },
        await getSobre(mirado.tareas_hilos),
        mirado.descripcion,
        enlaces
      )
    : [];

  return <MisionView pasos={pasos} cadena={cadena} enlaces={enlaces} pasoConFichas={mirado?.id ?? null} pestanas={pestanas} />;
}
