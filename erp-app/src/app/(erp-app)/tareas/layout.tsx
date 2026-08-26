import { ListTodo } from "lucide-react";
import { ModuleTabs } from "@/components/layout/ModuleTabs";
import {
  puedeVerAuditoria,
  puedeVerLista,
  puedeVerMision,
  puedeVerPlantillas,
  puedeVerProyectos,
} from "@/modules/tareas/permissions";
import { getTutorialVisto } from "@/modules/tareas/queries";
import { Tutorial } from "@/modules/tareas/components/Tutorial";

export default async function TareasLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const [lista, mision, proyectos, plantillas, auditoria, tutorialVisto] = await Promise.all([
    puedeVerLista(),
    puedeVerMision(),
    puedeVerProyectos(),
    puedeVerPlantillas(),
    puedeVerAuditoria(),
    getTutorialVisto(),
  ]);

  const tabs = [
    lista && { codigo: "tareas_lista", label: "Lista", href: "/tareas" },
    mision && { codigo: "tareas_mision", label: "Misión", href: "/tareas/mision" },
    proyectos && { codigo: "tareas_proyectos", label: "Proyectos", href: "/tareas/proyectos" },
    plantillas && { codigo: "tareas_plantillas", label: "Plantillas", href: "/tareas/plantillas" },
    auditoria && { codigo: "tareas_auditoria", label: "Auditoría", href: "/tareas/auditoria" },
  ].filter((t): t is { codigo: string; label: string; href: string } => Boolean(t));

  return (
    <div className="flex h-full flex-col">
      <div className="mb-4 flex items-center justify-between gap-3">
        <h1 className="t-h1 flex items-center gap-2.5">
          <ListTodo size={28} strokeWidth={1.75} className="text-brand-500 shrink-0" />
          Tareas
        </h1>
        <Tutorial vistos={tutorialVisto} />
      </div>
      <ModuleTabs modulo="tareas" tabs={tabs} />
      {children}
    </div>
  );
}
