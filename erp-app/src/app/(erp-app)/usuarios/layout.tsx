import { UsersRound } from "lucide-react";
import { Breadcrumb } from "@/components/layout/Breadcrumb";
import { ModuleTabs } from "@/components/layout/ModuleTabs";
import { puedeVerEquipos, puedeVerUsuarios } from "@/modules/usuarios/permissions";

export default async function UsuariosLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const [verUsuarios, verEquipos] = await Promise.all([puedeVerUsuarios(), puedeVerEquipos()]);
  const tabs = [
    ...(verUsuarios ? [{ codigo: "usuarios_ver", label: "Usuarios", href: "/usuarios" }] : []),
    ...(verEquipos ? [{ codigo: "usuarios_equipos", label: "Equipos", href: "/usuarios/equipos" }] : []),
  ];

  return (
    <div className="flex flex-col h-full">
      <Breadcrumb modulo="usuarios" tabs={tabs} />
      <h1 className="t-h1 mb-4 flex items-center gap-2.5">
        <UsersRound size={28} strokeWidth={1.75} className="text-brand-500 shrink-0" />
        Usuarios
      </h1>
      <ModuleTabs modulo="usuarios" tabs={tabs} />
      {children}
    </div>
  );
}
