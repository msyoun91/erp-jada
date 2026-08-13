import { ListTodo } from "lucide-react";
import { ModuleTabs } from "@/components/layout/ModuleTabs";
import {
  puedeVerAuditoria,
  puedeVerMisTareas,
  puedeVerPlantillas,
  puedeVerTodasLasTareas,
} from "@/modules/tareas/permissions";

export default async function TareasLayout({ children }: { children: React.ReactNode }) {
  const [misTareas, todas, plantillas, auditoria] = await Promise.all([
    puedeVerMisTareas(),
    puedeVerTodasLasTareas(),
    puedeVerPlantillas(),
    puedeVerAuditoria(),
  ]);

  const tabs = [
    ...(misTareas ? [{ codigo: "tareas_mistareas", label: "Mis Tareas", href: "/tareas" }] : []),
    ...(todas ? [{ codigo: "tareas_todas", label: "Todas las Tareas", href: "/tareas/todas" }] : []),
    ...(plantillas ? [{ codigo: "tareas_plantillas", label: "Plantillas", href: "/tareas/plantillas" }] : []),
    ...(auditoria ? [{ codigo: "tareas_auditoria", label: "Auditoría", href: "/tareas/auditoria" }] : []),
  ];

  return (
    <div className="flex flex-col h-full">
      <h1 className="t-h1 mb-4 flex items-center gap-2.5">
        <ListTodo size={28} strokeWidth={1.75} className="text-brand-500 shrink-0" />
        Tareas
      </h1>
      <ModuleTabs modulo="tareas" tabs={tabs} />
      {children}
    </div>
  );
}
