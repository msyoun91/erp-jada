import { Modulo } from "@/components/layout/Modulo";
import { puedeVerEquipo, puedeVerMision, puedeVerPlantillas, puedeVerTareas, puedeVerTodas } from "@/modules/tareas/permissions";

export default async function TareasLayout({ children }: { children: React.ReactNode }) {
  const [verHilos, verMision, verEquipo, verPlantillas, verTodas] = await Promise.all([
    puedeVerTareas(),
    puedeVerMision(),
    puedeVerEquipo(),
    puedeVerPlantillas(),
    puedeVerTodas(),
  ]);
  const tabs = [
    ...(verHilos ? [{ codigo: "tareas_ver", label: "Hilos", href: "/tareas" }] : []),
    ...(verMision ? [{ codigo: "tareas_mision", label: "Misión", href: "/tareas/mision" }] : []),
    ...(verEquipo ? [{ codigo: "tareas_equipo", label: "Equipo", href: "/tareas/equipo" }] : []),
    ...(verPlantillas ? [{ codigo: "tareas_plantillas", label: "Plantillas", href: "/tareas/plantillas" }] : []),
    ...(verTodas ? [{ codigo: "tareas_todas", label: "Todas", href: "/tareas/todas" }] : []),
  ];

  return (
    <Modulo modulo="tareas" tabs={tabs}>
      {children}
    </Modulo>
  );
}
