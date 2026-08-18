import { ListTodo } from "lucide-react";
import { ModuleTabs } from "@/components/layout/ModuleTabs";
import {
  puedeVerAuditoria,
  puedeVerLista,
  puedeVerPlantillas,
  puedeVerProyectos,
} from "@/modules/tareas/permissions";

export default async function TareasLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const [lista, proyectos, plantillas, auditoria] = await Promise.all([
    puedeVerLista(),
    puedeVerProyectos(),
    puedeVerPlantillas(),
    puedeVerAuditoria(),
  ]);

  const tabs = [
    lista && { codigo: "tareas_lista", label: "Mis tareas", href: "/tareas" },
    proyectos && { codigo: "tareas_proyectos", label: "Proyectos", href: "/tareas/proyectos" },
    plantillas && { codigo: "tareas_plantillas", label: "Plantillas", href: "/tareas/plantillas" },
    auditoria && { codigo: "tareas_auditoria", label: "Auditoría", href: "/tareas/auditoria" },
  ].filter((t): t is { codigo: string; label: string; href: string } => Boolean(t));

  return (
    <div className="flex h-full flex-col">
      <h1 className="t-h1 mb-4 flex items-center gap-2.5">
        <ListTodo size={28} strokeWidth={1.75} className="text-brand-500 shrink-0" />
        Tareas
      </h1>
      <ModuleTabs modulo="tareas" tabs={tabs} />
      {children}
    </div>
  );
}
