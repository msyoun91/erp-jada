import Image from "next/image";
import { createClient } from "@/lib/supabase/server";
import { getUserSubmodulos } from "@/lib/permissions";
import { getAvisos, getNotificaciones } from "@/modules/notificaciones/queries";
import { NotificacionesBell } from "@/modules/notificaciones/components/NotificacionesBell";
import { SidebarNav } from "./SidebarNav";
import { MobileNav } from "./MobileNav";

export async function Sidebar() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const [codigos, { data: usuario }, notificaciones, avisos] = await Promise.all([
    getUserSubmodulos(),
    supabase.from("usuarios").select("nombre").eq("id", user.id).single(),
    getNotificaciones(),
    getAvisos(),
  ]);

  const modulosVisibles = [...new Set(codigos.map((c) => c.split("_")[0]))];
  const nombre = usuario?.nombre ?? user.email ?? "";

  return (
    <>
      <aside className="hidden w-[220px] shrink-0 flex-col border-r border-border bg-bg-nav p-3 md:sticky md:top-0 md:flex md:h-screen">
        {/* La campanita queda arriba a la derecha en las dos superficies: acá y
            en la barra de MobileNav. En el drawer no va — estaría escondida
            detrás del botón que hay que apretar para verla. */}
        <div className="mb-4 flex items-center justify-between">
          <Image src="/logo.svg" alt="JADA" width={72} height={26} className="logo ml-1" priority />
          <NotificacionesBell notificaciones={notificaciones} avisos={avisos} />
        </div>
        <SidebarNav modulosVisibles={modulosVisibles} nombre={nombre} />
      </aside>
      <MobileNav
        modulosVisibles={modulosVisibles}
        nombre={nombre}
        notificaciones={notificaciones}
        avisos={avisos}
      />
    </>
  );
}
