import type { GuionTutorial } from "@/components/layout/Tutorial";

export const TUTORIAL_TAREAS: GuionTutorial = {
  "/tareas": [
    {
      codigo: "tareas_tabs",
      titulo: "El mismo trabajo, visto de varias formas",
      texto:
        "Hilos es el panorama de lo que trabajás. Misión te pasa tus pasos de a uno. Equipo es la bandeja del delegador, y Plantillas guarda trabajos que se repiten.",
    },
    {
      codigo: "tareas_ver_nuevo",
      titulo: "Un hilo es un trabajo con pasos",
      texto:
        "Quedás como responsable: lo cerrás vos cuando todo está hecho. Cada paso tiene un asignado, y si es de otro equipo, le llega como pedido para aceptar o rechazar.",
    },
    {
      codigo: "tareas_ver_lista",
      titulo: "Solo donde participás",
      texto:
        "Ves los hilos donde sos responsable o tenés algún paso asignado, enteros. Un clic abre el hilo con todos sus pasos y notas.",
    },
  ],
  "/tareas/[id]": [
    {
      codigo: "tareas_hilo_cabecera",
      titulo: "Responsable y «Sobre»",
      texto:
        "El responsable es dueño del hilo y lo cierra. «Sobre» lo ata a una obra u otro registro, si nació de ahí. El ⋯ edita, transfiere o reabre.",
    },
    {
      codigo: "tareas_hilo_pasos",
      titulo: "Pasos encadenados",
      texto:
        "Un paso con «paso anterior» espera a que ese se complete: hasta entonces está bloqueado y no aparece en Misión. Sin anterior, corre en paralelo. Completado, se corrige con una nota o se reabre.",
    },
  ],
  "/tareas/mision": [
    {
      codigo: "tareas_mision_cola",
      titulo: "De a uno, por prioridad",
      texto:
        "Misión arma la cola con tus pasos abiertos: primero la prioridad, después lo que vence antes. Las flechas ← → del teclado también avanzan.",
    },
    {
      codigo: "tareas_mision_acciones",
      titulo: "Decidí sin abrir el hilo",
      texto:
        "Un pedido se acepta o se rechaza con motivo. Lo aceptado se completa o se pone en espera hasta una fecha. «Abrir en el hilo» lleva al contexto completo.",
    },
    {
      codigo: "tareas_mision_esperan",
      titulo: "Lo que espera no entra en la cola",
      texto:
        "Un paso bloqueado por el anterior, o en espera, no está en la cola: está acá abajo, con el motivo. Así una cola vacía no esconde trabajo.",
    },
  ],
  "/tareas/equipo": [
    {
      codigo: "tareas_equipo_tipos",
      titulo: "La bandeja del equipo",
      texto:
        "Pedidos: lo que otros le piden a tu equipo o a un miembro, para aceptar, rechazar o repartir. Al equipo: lo aceptado que todavía no es de nadie. Hilos: donde participa tu equipo.",
    },
  ],
  "/tareas/plantillas": [
    {
      codigo: "tareas_plantillas_nueva",
      titulo: "Un trabajo que se repite",
      texto:
        "Una plantilla guarda los pasos de un trabajo, en orden. Usarla crea el hilo de una, con los pasos encadenados. Es tuya: solo vos la usás.",
    },
    {
      codigo: "tareas_plantillas_ver",
      titulo: "Compartir es publicar",
      texto:
        "Publicar una plantilla la pone en el Catálogo: los demás la leen y se hacen una copia propia, que no cambia cuando cambia la tuya.",
    },
  ],
  "/tareas/todas": [
    {
      codigo: "tareas_todas_filtro",
      titulo: "Todos los hilos",
      texto:
        "Como administrador ves todos. «Huérfanos» son los de un responsable que ya no puede recibirlos: abrilos y transferilos.",
    },
  ],
};
