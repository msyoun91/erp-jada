import { ListTodo } from "lucide-react";
import { Breadcrumb } from "@/components/layout/Breadcrumb";
import { ModuleTabs } from "@/components/layout/ModuleTabs";
import { puedeVerMision, puedeVerTareas } from "@/modules/tareas/permissions";

export default async function TareasLayout({ children }: { children: React.ReactNode }) {
  const [verHilos, verMision] = await Promise.all([puedeVerTareas(), puedeVerMision()]);
  const tabs = [
    ...(verHilos ? [{ codigo: "tareas_ver", label: "Hilos", href: "/tareas" }] : []),
    ...(verMision ? [{ codigo: "tareas_mision", label: "Misión", href: "/tareas/mision" }] : []),
  ];

  return (
    <div className="flex flex-col h-full">
      <Breadcrumb modulo="tareas" tabs={tabs} />
      <h1 className="t-h1 mb-4 flex items-center gap-2.5">
        <ListTodo size={28} strokeWidth={1.75} className="text-brand-500 shrink-0" />
        Tareas
      </h1>
      <ModuleTabs modulo="tareas" tabs={tabs} />
      {children}
    </div>
  );
}
