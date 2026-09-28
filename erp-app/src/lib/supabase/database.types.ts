export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      contactos_accesos: {
        Row: {
          created_at: string
          id: string
          persona_id: string
          usuario_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          persona_id: string
          usuario_id: string
        }
        Update: {
          created_at?: string
          id?: string
          persona_id?: string
          usuario_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "contactos_accesos_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "contactos_personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_accesos_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      contactos_ediciones: {
        Row: {
          actor_id: string | null
          anterior: string | null
          campo: string
          created_at: string
          empresa_id: string | null
          id: string
          nuevo: string | null
          persona_id: string | null
        }
        Insert: {
          actor_id?: string | null
          anterior?: string | null
          campo: string
          created_at?: string
          empresa_id?: string | null
          id?: string
          nuevo?: string | null
          persona_id?: string | null
        }
        Update: {
          actor_id?: string | null
          anterior?: string | null
          campo?: string
          created_at?: string
          empresa_id?: string | null
          id?: string
          nuevo?: string | null
          persona_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "contactos_ediciones_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_ediciones_empresa_id_fkey"
            columns: ["empresa_id"]
            isOneToOne: false
            referencedRelation: "contactos_empresas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_ediciones_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "contactos_personas"
            referencedColumns: ["id"]
          },
        ]
      }
      contactos_empresa_equipos: {
        Row: {
          activo: boolean
          compartida_por: string
          created_at: string
          empresa_id: string
          equipo_id: string
          id: string
          updated_at: string
        }
        Insert: {
          activo?: boolean
          compartida_por: string
          created_at?: string
          empresa_id: string
          equipo_id: string
          id?: string
          updated_at?: string
        }
        Update: {
          activo?: boolean
          compartida_por?: string
          created_at?: string
          empresa_id?: string
          equipo_id?: string
          id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "contactos_empresa_equipos_compartida_por_fkey"
            columns: ["compartida_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_empresa_equipos_empresa_id_fkey"
            columns: ["empresa_id"]
            isOneToOne: false
            referencedRelation: "contactos_empresas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_empresa_equipos_equipo_id_fkey"
            columns: ["equipo_id"]
            isOneToOne: false
            referencedRelation: "equipos"
            referencedColumns: ["id"]
          },
        ]
      }
      contactos_empresas: {
        Row: {
          activo: boolean
          congelada: boolean
          congelada_antes: Json | null
          creado_por: string
          created_at: string
          email: string | null
          equipo_id: string | null
          id: string
          misma_que: string | null
          nombre: string
          notas: string | null
          rechazo_motivo: string | null
          telefono: string | null
          updated_at: string
          web: string | null
        }
        Insert: {
          activo?: boolean
          congelada?: boolean
          congelada_antes?: Json | null
          creado_por?: string
          created_at?: string
          email?: string | null
          equipo_id?: string | null
          id?: string
          misma_que?: string | null
          nombre: string
          notas?: string | null
          rechazo_motivo?: string | null
          telefono?: string | null
          updated_at?: string
          web?: string | null
        }
        Update: {
          activo?: boolean
          congelada?: boolean
          congelada_antes?: Json | null
          creado_por?: string
          created_at?: string
          email?: string | null
          equipo_id?: string | null
          id?: string
          misma_que?: string | null
          nombre?: string
          notas?: string | null
          rechazo_motivo?: string | null
          telefono?: string | null
          updated_at?: string
          web?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "contactos_empresas_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_empresas_equipo_id_fkey"
            columns: ["equipo_id"]
            isOneToOne: false
            referencedRelation: "equipos"
            referencedColumns: ["id"]
          },
        ]
      }
      contactos_persona_empresa: {
        Row: {
          activo: boolean
          cargo: string | null
          creado_por: string | null
          created_at: string
          desde: string
          empresa_id: string
          hasta: string | null
          id: string
          persona_id: string
          updated_at: string
        }
        Insert: {
          activo?: boolean
          cargo?: string | null
          creado_por?: string | null
          created_at?: string
          desde?: string
          empresa_id: string
          hasta?: string | null
          id?: string
          persona_id: string
          updated_at?: string
        }
        Update: {
          activo?: boolean
          cargo?: string | null
          creado_por?: string | null
          created_at?: string
          desde?: string
          empresa_id?: string
          hasta?: string | null
          id?: string
          persona_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "contactos_persona_empresa_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_persona_empresa_empresa_id_fkey"
            columns: ["empresa_id"]
            isOneToOne: false
            referencedRelation: "contactos_empresas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_persona_empresa_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "contactos_personas"
            referencedColumns: ["id"]
          },
        ]
      }
      contactos_personas: {
        Row: {
          activo: boolean
          congelada: boolean
          congelada_antes: Json | null
          creado_por: string
          created_at: string
          email: string | null
          id: string
          misma_que: string | null
          nombre: string
          notas: string | null
          rechazo_motivo: string | null
          responsable_id: string
          telefono: string | null
          updated_at: string
        }
        Insert: {
          activo?: boolean
          congelada?: boolean
          congelada_antes?: Json | null
          creado_por?: string
          created_at?: string
          email?: string | null
          id?: string
          misma_que?: string | null
          nombre: string
          notas?: string | null
          rechazo_motivo?: string | null
          responsable_id?: string
          telefono?: string | null
          updated_at?: string
        }
        Update: {
          activo?: boolean
          congelada?: boolean
          congelada_antes?: Json | null
          creado_por?: string
          created_at?: string
          email?: string | null
          id?: string
          misma_que?: string | null
          nombre?: string
          notas?: string | null
          rechazo_motivo?: string | null
          responsable_id?: string
          telefono?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "contactos_personas_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_personas_responsable_id_fkey"
            columns: ["responsable_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      contactos_vinculos: {
        Row: {
          activo: boolean
          creado_por: string | null
          created_at: string
          desde: string
          empresa_id: string | null
          ente: string
          hasta: string | null
          id: string
          persona_id: string | null
          registro_id: string
          roles: string[]
          updated_at: string
        }
        Insert: {
          activo?: boolean
          creado_por?: string | null
          created_at?: string
          desde?: string
          empresa_id?: string | null
          ente: string
          hasta?: string | null
          id?: string
          persona_id?: string | null
          registro_id: string
          roles: string[]
          updated_at?: string
        }
        Update: {
          activo?: boolean
          creado_por?: string | null
          created_at?: string
          desde?: string
          empresa_id?: string | null
          ente?: string
          hasta?: string | null
          id?: string
          persona_id?: string | null
          registro_id?: string
          roles?: string[]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "contactos_vinculos_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_vinculos_empresa_id_fkey"
            columns: ["empresa_id"]
            isOneToOne: false
            referencedRelation: "contactos_empresas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contactos_vinculos_ente_fkey"
            columns: ["ente"]
            isOneToOne: false
            referencedRelation: "entes"
            referencedColumns: ["codigo"]
          },
          {
            foreignKeyName: "contactos_vinculos_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "contactos_personas"
            referencedColumns: ["id"]
          },
        ]
      }
      contactos_vinculos_guardados: {
        Row: {
          a_empresa_id: string | null
          activo: boolean
          cargado_por: string
          cargo: string | null
          created_at: string
          empresa_id: string | null
          ente: string | null
          id: string
          persona_id: string | null
          registro_id: string | null
          resultado: string | null
          roles: string[] | null
          updated_at: string
        }
        Insert: {
          a_empresa_id?: string | null
          activo?: boolean
          cargado_por: string
          cargo?: string | null
          created_at?: string
          empresa_id?: string | null
          ente?: string | null
          id?: string
          persona_id?: string | null
          registro_id?: string | null
          resultado?: string | null
          roles?: string[] | null
          updated_at?: string
        }
        Update: {
          a_empresa_id?: string | null
          activo?: boolean
          cargado_por?: string
          cargo?: string | null
          created_at?: string
          empresa_id?: string | null
          ente?: string | null
          id?: string
          persona_id?: string | null
          registro_id?: string | null
          resultado?: string | null
          roles?: string[] | null
          updated_at?: string
        }
        Relationships: []
      }
      entes: {
        Row: {
          activo: boolean
          codigo: string
          created_at: string
          datos: string[]
          disparos: Database["public"]["Enums"]["tipo_evento"][]
          estados: unknown
          id: string
          modulo: string
          roles: string[]
          ruta: string
          submodulo: string
          tabla: unknown
          updated_at: string
        }
        Insert: {
          activo?: boolean
          codigo: string
          created_at?: string
          datos?: string[]
          disparos?: Database["public"]["Enums"]["tipo_evento"][]
          estados?: unknown
          id?: string
          modulo: string
          roles?: string[]
          ruta: string
          submodulo: string
          tabla: unknown
          updated_at?: string
        }
        Update: {
          activo?: boolean
          codigo?: string
          created_at?: string
          datos?: string[]
          disparos?: Database["public"]["Enums"]["tipo_evento"][]
          estados?: unknown
          id?: string
          modulo?: string
          roles?: string[]
          ruta?: string
          submodulo?: string
          tabla?: unknown
          updated_at?: string
        }
        Relationships: []
      }
      equipos: {
        Row: {
          activo: boolean
          created_at: string
          id: string
          nombre: string
          updated_at: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          id?: string
          nombre: string
          updated_at?: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          id?: string
          nombre?: string
          updated_at?: string
        }
        Relationships: []
      }
      equipos_miembros: {
        Row: {
          activo: boolean
          created_at: string
          equipo_id: string
          id: string
          updated_at: string
          usuario_id: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          equipo_id: string
          id?: string
          updated_at?: string
          usuario_id: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          equipo_id?: string
          id?: string
          updated_at?: string
          usuario_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "equipos_miembros_equipo_id_fkey"
            columns: ["equipo_id"]
            isOneToOne: false
            referencedRelation: "equipos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "equipos_miembros_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      eventos: {
        Row: {
          actor_id: string | null
          created_at: string
          detalle: Json
          ente: string
          evento: Database["public"]["Enums"]["tipo_evento"]
          id: string
          registro_id: string
        }
        Insert: {
          actor_id?: string | null
          created_at?: string
          detalle?: Json
          ente: string
          evento: Database["public"]["Enums"]["tipo_evento"]
          id?: string
          registro_id: string
        }
        Update: {
          actor_id?: string | null
          created_at?: string
          detalle?: Json
          ente?: string
          evento?: Database["public"]["Enums"]["tipo_evento"]
          id?: string
          registro_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "eventos_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "eventos_ente_fkey"
            columns: ["ente"]
            isOneToOne: false
            referencedRelation: "entes"
            referencedColumns: ["codigo"]
          },
        ]
      }
      obras: {
        Row: {
          activo: boolean
          compra_estimada: string | null
          congelada: boolean
          congelada_antes: Json | null
          creado_por: string
          created_at: string
          direccion: string
          equipo_id: string | null
          estado: Database["public"]["Enums"]["estado_obra"]
          estado_nota: string | null
          id: string
          localidad: string | null
          misma_que: string | null
          motivo_perdida: Database["public"]["Enums"]["motivo_perdida"] | null
          nombre: string
          notas: string | null
          origen: Database["public"]["Enums"]["origen_obra"]
          rechazo_motivo: string | null
          responsable_id: string
          tipo: Database["public"]["Enums"]["tipo_obra"]
          updated_at: string
        }
        Insert: {
          activo?: boolean
          compra_estimada?: string | null
          congelada?: boolean
          congelada_antes?: Json | null
          creado_por?: string
          created_at?: string
          direccion: string
          equipo_id?: string | null
          estado?: Database["public"]["Enums"]["estado_obra"]
          estado_nota?: string | null
          id?: string
          localidad?: string | null
          misma_que?: string | null
          motivo_perdida?: Database["public"]["Enums"]["motivo_perdida"] | null
          nombre: string
          notas?: string | null
          origen: Database["public"]["Enums"]["origen_obra"]
          rechazo_motivo?: string | null
          responsable_id?: string
          tipo: Database["public"]["Enums"]["tipo_obra"]
          updated_at?: string
        }
        Update: {
          activo?: boolean
          compra_estimada?: string | null
          congelada?: boolean
          congelada_antes?: Json | null
          creado_por?: string
          created_at?: string
          direccion?: string
          equipo_id?: string | null
          estado?: Database["public"]["Enums"]["estado_obra"]
          estado_nota?: string | null
          id?: string
          localidad?: string | null
          misma_que?: string | null
          motivo_perdida?: Database["public"]["Enums"]["motivo_perdida"] | null
          nombre?: string
          notas?: string | null
          origen?: Database["public"]["Enums"]["origen_obra"]
          rechazo_motivo?: string | null
          responsable_id?: string
          tipo?: Database["public"]["Enums"]["tipo_obra"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "obras_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "obras_equipo_id_fkey"
            columns: ["equipo_id"]
            isOneToOne: false
            referencedRelation: "equipos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "obras_responsable_id_fkey"
            columns: ["responsable_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      obras_participantes: {
        Row: {
          activo: boolean
          agregado_por: string | null
          created_at: string
          equipo_id: string | null
          id: string
          obra_id: string
          updated_at: string
          usuario_id: string
        }
        Insert: {
          activo?: boolean
          agregado_por?: string | null
          created_at?: string
          equipo_id?: string | null
          id?: string
          obra_id: string
          updated_at?: string
          usuario_id: string
        }
        Update: {
          activo?: boolean
          agregado_por?: string | null
          created_at?: string
          equipo_id?: string | null
          id?: string
          obra_id?: string
          updated_at?: string
          usuario_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "obras_participantes_agregado_por_fkey"
            columns: ["agregado_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "obras_participantes_equipo_id_fkey"
            columns: ["equipo_id"]
            isOneToOne: false
            referencedRelation: "equipos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "obras_participantes_obra_id_fkey"
            columns: ["obra_id"]
            isOneToOne: false
            referencedRelation: "obras"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "obras_participantes_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      submodulo_reglas: {
        Row: {
          activo: boolean
          id: string
          otro_id: string
          submodulo_id: string
          tipo: Database["public"]["Enums"]["tipo_regla_submodulo"]
        }
        Insert: {
          activo?: boolean
          id?: string
          otro_id: string
          submodulo_id: string
          tipo: Database["public"]["Enums"]["tipo_regla_submodulo"]
        }
        Update: {
          activo?: boolean
          id?: string
          otro_id?: string
          submodulo_id?: string
          tipo?: Database["public"]["Enums"]["tipo_regla_submodulo"]
        }
        Relationships: [
          {
            foreignKeyName: "submodulo_reglas_otro_id_fkey"
            columns: ["otro_id"]
            isOneToOne: false
            referencedRelation: "submodulos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "submodulo_reglas_submodulo_id_fkey"
            columns: ["submodulo_id"]
            isOneToOne: false
            referencedRelation: "submodulos"
            referencedColumns: ["id"]
          },
        ]
      }
      submodulos: {
        Row: {
          activo: boolean
          codigo: string
          created_at: string
          delegable: boolean
          id: string
          modulo: string
          nombre: string
          orden: number
          tipo: Database["public"]["Enums"]["tipo_submodulo"]
          updated_at: string
          vista_id: string | null
        }
        Insert: {
          activo?: boolean
          codigo: string
          created_at?: string
          delegable?: boolean
          id?: string
          modulo: string
          nombre: string
          orden?: number
          tipo: Database["public"]["Enums"]["tipo_submodulo"]
          updated_at?: string
          vista_id?: string | null
        }
        Update: {
          activo?: boolean
          codigo?: string
          created_at?: string
          delegable?: boolean
          id?: string
          modulo?: string
          nombre?: string
          orden?: number
          tipo?: Database["public"]["Enums"]["tipo_submodulo"]
          updated_at?: string
          vista_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "submodulos_vista_id_fkey"
            columns: ["vista_id"]
            isOneToOne: false
            referencedRelation: "submodulos"
            referencedColumns: ["id"]
          },
        ]
      }
      tareas: {
        Row: {
          activo: boolean
          asignado_equipo_id: string | null
          asignado_id: string | null
          created_at: string
          descripcion: string | null
          equipo_id: string | null
          espera_hasta: string | null
          espera_motivo: string | null
          estado: Database["public"]["Enums"]["estado_tarea"]
          hilo_id: string
          id: string
          motivo_rechazo: string | null
          paso_anterior_id: string | null
          prioridad: Database["public"]["Enums"]["prioridad_tarea"]
          resultado: string | null
          titulo: string
          updated_at: string
          vence: string | null
          vence_dias: number | null
        }
        Insert: {
          activo?: boolean
          asignado_equipo_id?: string | null
          asignado_id?: string | null
          created_at?: string
          descripcion?: string | null
          equipo_id?: string | null
          espera_hasta?: string | null
          espera_motivo?: string | null
          estado?: Database["public"]["Enums"]["estado_tarea"]
          hilo_id: string
          id?: string
          motivo_rechazo?: string | null
          paso_anterior_id?: string | null
          prioridad?: Database["public"]["Enums"]["prioridad_tarea"]
          resultado?: string | null
          titulo: string
          updated_at?: string
          vence?: string | null
          vence_dias?: number | null
        }
        Update: {
          activo?: boolean
          asignado_equipo_id?: string | null
          asignado_id?: string | null
          created_at?: string
          descripcion?: string | null
          equipo_id?: string | null
          espera_hasta?: string | null
          espera_motivo?: string | null
          estado?: Database["public"]["Enums"]["estado_tarea"]
          hilo_id?: string
          id?: string
          motivo_rechazo?: string | null
          paso_anterior_id?: string | null
          prioridad?: Database["public"]["Enums"]["prioridad_tarea"]
          resultado?: string | null
          titulo?: string
          updated_at?: string
          vence?: string | null
          vence_dias?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "tareas_asignado_equipo_id_fkey"
            columns: ["asignado_equipo_id"]
            isOneToOne: false
            referencedRelation: "equipos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_asignado_id_fkey"
            columns: ["asignado_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_equipo_id_fkey"
            columns: ["equipo_id"]
            isOneToOne: false
            referencedRelation: "equipos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_hilo_id_fkey"
            columns: ["hilo_id"]
            isOneToOne: false
            referencedRelation: "tareas_hilos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_paso_anterior_fk"
            columns: ["paso_anterior_id", "hilo_id"]
            isOneToOne: false
            referencedRelation: "tareas"
            referencedColumns: ["id", "hilo_id"]
          },
        ]
      }
      tareas_ediciones: {
        Row: {
          activo: boolean
          actor_id: string | null
          anterior: string | null
          campo: string
          created_at: string
          hilo_id: string
          id: string
          nuevo: string | null
          ocultada_at: string | null
          ocultada_por: string | null
          tarea_id: string | null
          updated_at: string
        }
        Insert: {
          activo?: boolean
          actor_id?: string | null
          anterior?: string | null
          campo: string
          created_at?: string
          hilo_id: string
          id?: string
          nuevo?: string | null
          ocultada_at?: string | null
          ocultada_por?: string | null
          tarea_id?: string | null
          updated_at?: string
        }
        Update: {
          activo?: boolean
          actor_id?: string | null
          anterior?: string | null
          campo?: string
          created_at?: string
          hilo_id?: string
          id?: string
          nuevo?: string | null
          ocultada_at?: string | null
          ocultada_por?: string | null
          tarea_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tareas_ediciones_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_ediciones_hilo_id_fkey"
            columns: ["hilo_id"]
            isOneToOne: false
            referencedRelation: "tareas_hilos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_ediciones_ocultada_por_fkey"
            columns: ["ocultada_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_ediciones_tarea_fk"
            columns: ["tarea_id", "hilo_id"]
            isOneToOne: false
            referencedRelation: "tareas"
            referencedColumns: ["id", "hilo_id"]
          },
        ]
      }
      tareas_hilos: {
        Row: {
          activo: boolean
          created_at: string
          equipo_id: string | null
          estado: Database["public"]["Enums"]["estado_hilo"]
          id: string
          recurrencia_cantidad: number | null
          recurrencia_de: string | null
          recurrencia_unidad:
            | Database["public"]["Enums"]["recurrencia_unidad"]
            | null
          responsable_id: string
          resultado: string | null
          titulo: string
          updated_at: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          equipo_id?: string | null
          estado?: Database["public"]["Enums"]["estado_hilo"]
          id?: string
          recurrencia_cantidad?: number | null
          recurrencia_de?: string | null
          recurrencia_unidad?:
            | Database["public"]["Enums"]["recurrencia_unidad"]
            | null
          responsable_id?: string
          resultado?: string | null
          titulo: string
          updated_at?: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          equipo_id?: string | null
          estado?: Database["public"]["Enums"]["estado_hilo"]
          id?: string
          recurrencia_cantidad?: number | null
          recurrencia_de?: string | null
          recurrencia_unidad?:
            | Database["public"]["Enums"]["recurrencia_unidad"]
            | null
          responsable_id?: string
          resultado?: string | null
          titulo?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tareas_hilos_equipo_id_fkey"
            columns: ["equipo_id"]
            isOneToOne: false
            referencedRelation: "equipos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_hilos_recurrencia_de_fkey"
            columns: ["recurrencia_de"]
            isOneToOne: false
            referencedRelation: "tareas_hilos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_hilos_responsable_id_fkey"
            columns: ["responsable_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      tareas_notas: {
        Row: {
          activo: boolean
          autor_id: string
          created_at: string
          hilo_id: string
          id: string
          ocultada_at: string | null
          ocultada_por: string | null
          tarea_id: string | null
          texto: string
          updated_at: string
        }
        Insert: {
          activo?: boolean
          autor_id?: string
          created_at?: string
          hilo_id: string
          id?: string
          ocultada_at?: string | null
          ocultada_por?: string | null
          tarea_id?: string | null
          texto: string
          updated_at?: string
        }
        Update: {
          activo?: boolean
          autor_id?: string
          created_at?: string
          hilo_id?: string
          id?: string
          ocultada_at?: string | null
          ocultada_por?: string | null
          tarea_id?: string | null
          texto?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tareas_notas_autor_id_fkey"
            columns: ["autor_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_notas_hilo_id_fkey"
            columns: ["hilo_id"]
            isOneToOne: false
            referencedRelation: "tareas_hilos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_notas_ocultada_por_fkey"
            columns: ["ocultada_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_notas_tarea_fk"
            columns: ["tarea_id", "hilo_id"]
            isOneToOne: false
            referencedRelation: "tareas"
            referencedColumns: ["id", "hilo_id"]
          },
        ]
      }
      tareas_plantillas: {
        Row: {
          activo: boolean
          copiada_de: string | null
          created_at: string
          descripcion: string | null
          dueno_id: string
          id: string
          nombre: string
          publicada: boolean
          updated_at: string
        }
        Insert: {
          activo?: boolean
          copiada_de?: string | null
          created_at?: string
          descripcion?: string | null
          dueno_id?: string
          id?: string
          nombre: string
          publicada?: boolean
          updated_at?: string
        }
        Update: {
          activo?: boolean
          copiada_de?: string | null
          created_at?: string
          descripcion?: string | null
          dueno_id?: string
          id?: string
          nombre?: string
          publicada?: boolean
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tareas_plantillas_copiada_de_fkey"
            columns: ["copiada_de"]
            isOneToOne: false
            referencedRelation: "tareas_plantillas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_plantillas_dueno_id_fkey"
            columns: ["dueno_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      tareas_plantillas_pasos: {
        Row: {
          activo: boolean
          asignado_equipo_id: string | null
          asignado_id: string | null
          created_at: string
          descripcion: string | null
          espera_anterior: boolean
          id: string
          orden: number
          plantilla_id: string
          prioridad: Database["public"]["Enums"]["prioridad_tarea"]
          titulo: string
          updated_at: string
          vence_dias: number | null
        }
        Insert: {
          activo?: boolean
          asignado_equipo_id?: string | null
          asignado_id?: string | null
          created_at?: string
          descripcion?: string | null
          espera_anterior?: boolean
          id?: string
          orden: number
          plantilla_id: string
          prioridad?: Database["public"]["Enums"]["prioridad_tarea"]
          titulo: string
          updated_at?: string
          vence_dias?: number | null
        }
        Update: {
          activo?: boolean
          asignado_equipo_id?: string | null
          asignado_id?: string | null
          created_at?: string
          descripcion?: string | null
          espera_anterior?: boolean
          id?: string
          orden?: number
          plantilla_id?: string
          prioridad?: Database["public"]["Enums"]["prioridad_tarea"]
          titulo?: string
          updated_at?: string
          vence_dias?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "tareas_plantillas_pasos_asignado_equipo_id_fkey"
            columns: ["asignado_equipo_id"]
            isOneToOne: false
            referencedRelation: "equipos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_plantillas_pasos_asignado_id_fkey"
            columns: ["asignado_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_plantillas_pasos_plantilla_id_fkey"
            columns: ["plantilla_id"]
            isOneToOne: false
            referencedRelation: "tareas_plantillas"
            referencedColumns: ["id"]
          },
        ]
      }
      tareas_vinculos: {
        Row: {
          activo: boolean
          created_at: string
          ente: string
          id: string
          registro_id: string
          tarea_id: string
          updated_at: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          ente: string
          id?: string
          registro_id: string
          tarea_id: string
          updated_at?: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          ente?: string
          id?: string
          registro_id?: string
          tarea_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tareas_vinculos_ente_fkey"
            columns: ["ente"]
            isOneToOne: false
            referencedRelation: "entes"
            referencedColumns: ["codigo"]
          },
          {
            foreignKeyName: "tareas_vinculos_tarea_id_fkey"
            columns: ["tarea_id"]
            isOneToOne: false
            referencedRelation: "tareas"
            referencedColumns: ["id"]
          },
        ]
      }
      usuario_notificaciones: {
        Row: {
          activo: boolean
          actor_id: string | null
          created_at: string
          entidad: string
          entidad_id: string
          id: string
          leida_at: string | null
          tipo: Database["public"]["Enums"]["tipo_notificacion"]
          updated_at: string
          usuario_id: string
        }
        Insert: {
          activo?: boolean
          actor_id?: string | null
          created_at?: string
          entidad: string
          entidad_id: string
          id?: string
          leida_at?: string | null
          tipo: Database["public"]["Enums"]["tipo_notificacion"]
          updated_at?: string
          usuario_id: string
        }
        Update: {
          activo?: boolean
          actor_id?: string | null
          created_at?: string
          entidad?: string
          entidad_id?: string
          id?: string
          leida_at?: string | null
          tipo?: Database["public"]["Enums"]["tipo_notificacion"]
          updated_at?: string
          usuario_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "usuario_notificaciones_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "usuario_notificaciones_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      usuario_submodulos: {
        Row: {
          activo: boolean
          created_at: string
          id: string
          otorgada_por: string | null
          submodulo_id: string
          updated_at: string
          usuario_id: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          id?: string
          otorgada_por?: string | null
          submodulo_id: string
          updated_at?: string
          usuario_id: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          id?: string
          otorgada_por?: string | null
          submodulo_id?: string
          updated_at?: string
          usuario_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "usuario_submodulos_otorgada_por_fkey"
            columns: ["otorgada_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "usuario_submodulos_submodulo_id_fkey"
            columns: ["submodulo_id"]
            isOneToOne: false
            referencedRelation: "submodulos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "usuario_submodulos_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      usuario_tutorial: {
        Row: {
          created_at: string
          id: string
          paso: string
          updated_at: string
          usuario_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          paso: string
          updated_at?: string
          usuario_id: string
        }
        Update: {
          created_at?: string
          id?: string
          paso?: string
          updated_at?: string
          usuario_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "usuario_tutorial_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      usuario_widgets: {
        Row: {
          created_at: string
          id: string
          updated_at: string
          usuario_id: string
          visible: boolean
          widget_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          updated_at?: string
          usuario_id: string
          visible?: boolean
          widget_id: string
        }
        Update: {
          created_at?: string
          id?: string
          updated_at?: string
          usuario_id?: string
          visible?: boolean
          widget_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "usuario_widgets_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      usuarios: {
        Row: {
          activo: boolean
          created_at: string
          email: string
          id: string
          nombre: string
          telefono: string | null
          updated_at: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          email: string
          id: string
          nombre: string
          telefono?: string | null
          updated_at?: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          email?: string
          id?: string
          nombre?: string
          telefono?: string | null
          updated_at?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      asignar_equipo: {
        Args: {
          p_admin: string
          p_agenda_al_jefe?: boolean
          p_equipo: string | null
          p_usuario: string
        }
        Returns: undefined
      }
      asignar_submodulos: {
        Args: {
          p_admin: string
          p_submodulos: string[]
          p_tomar?: string[]
          p_usuario: string
        }
        Returns: undefined
      }
      buscar_registros: {
        Args: { p_modulo: string; p_texto: string }
        Returns: {
          detalle: string
          ente: string
          etiqueta: string
          href: string
          registro_id: string
        }[]
      }
      contactos_buscar: {
        Args: { p_texto: string }
        Returns: {
          id: string
          subtitulo: string
          tipo: string
          titulo: string
        }[]
      }
      contactos_compartir_empresa: {
        Args: { p_compartir: boolean; p_empresa: string; p_equipo: string }
        Returns: undefined
      }
      contactos_crear_y_vincular: {
        Args: {
          p_cargo?: string
          p_email?: string
          p_empresa_id?: string
          p_empresa_nombre?: string
          p_ente: string
          p_nombre: string
          p_registro: string
          p_roles: string[]
          p_telefono?: string
          p_tipo: string
        }
        Returns: string
      }
      contactos_desactivar_empresa: {
        Args: { p_empresa: string }
        Returns: undefined
      }
      contactos_desactivar_persona: {
        Args: { p_persona: string }
        Returns: undefined
      }
      contactos_desactivar_persona_empresa: {
        Args: { p_relacion: string }
        Returns: undefined
      }
      contactos_desactivar_vinculo: {
        Args: { p_vinculo: string }
        Returns: undefined
      }
      contactos_empresa_de_mi_equipo: {
        Args: { p_creado_por: string; p_empresa: string; p_equipo: string }
        Returns: boolean
      }
      contactos_equipos: {
        Args: never
        Returns: {
          id: string
          nombre: string
        }[]
      }
      contactos_etiqueta: {
        Args: { p_id: string; p_tipo: string }
        Returns: string
      }
      contactos_historial_contacto: {
        Args: { p_persona: string }
        Returns: {
          actor_id: string
          anterior: string
          campo: string
          created_at: string
          nuevo: string
        }[]
      }
      contactos_nombres: {
        Args: never
        Returns: {
          id: string
          nombre: string
        }[]
      }
      contactos_puede_abrir: {
        Args: { p_id: string; p_tipo: string; p_usuario: string }
        Returns: boolean
      }
      contactos_puede_ver_empresa: {
        Args: {
          p_activo: boolean
          p_creado_por: string
          p_empresa: string
          p_equipo: string
        }
        Returns: boolean
      }
      contactos_puede_ver_empresa_de: {
        Args: {
          p_activo: boolean
          p_creado_por: string
          p_empresa: string
          p_equipo: string
          p_usuario: string
        }
        Returns: boolean
      }
      contactos_puede_ver_persona: {
        Args: { p_activo: boolean; p_persona: string; p_responsable: string }
        Returns: boolean
      }
      contactos_puede_ver_persona_de: {
        Args: {
          p_activo: boolean
          p_persona: string
          p_responsable: string
          p_usuario: string
        }
        Returns: boolean
      }
      contactos_puede_ver_relacion: {
        Args: { p_contacto: string; p_ente: string; p_id: string }
        Returns: boolean
      }
      contactos_registrar_acceso: {
        Args: { p_persona: string }
        Returns: undefined
      }
      contactos_transferir_persona: {
        Args: { p_persona: string; p_responsable: string }
        Returns: undefined
      }
      contactos_ver_contacto: {
        Args: { p_persona: string }
        Returns: {
          email: string
          telefono: string
        }[]
      }
      contactos_parecidas: {
        Args: {
          p_email?: string
          p_id?: string
          p_nombre: string
          p_telefono?: string
          p_tipo: string
        }
        Returns: {
          coincide: string[]
          dueno: string
          equipo: string
          id: string
          nombre: string
        }[]
      }
      contactos_por_aprobar: {
        Args: never
        Returns: {
          antes: Json
          created_at: string
          dueno: string
          equipo: string
          guardados: Json
          id: string
          nombre: string
          notas: string
          parecidas: Json
          tipo: string
        }[]
      }
      contactos_resolver: {
        Args: {
          p_decision: string
          p_existente?: string
          p_id: string
          p_motivo?: string
          p_tipo: string
          p_vincular?: boolean
        }
        Returns: undefined
      }
      contactos_vinculables: {
        Args: { p_texto: string }
        Returns: {
          detalle: string
          id: string
          nombre: string
          tipo: string
        }[]
      }
      copiar_plantilla: { Args: { p_plantilla: string }; Returns: string }
      delegar_submodulos: {
        Args: { p_submodulos: string[]; p_usuario: string }
        Returns: undefined
      }
      designar_delegador: {
        Args: { p_admin: string; p_usuario: string }
        Returns: undefined
      }
      duplicados_avisos: {
        Args: never
        Returns: {
          destino: string
          destino_id: string
          etiqueta: string
          motivo: string
          notificacion_id: string
        }[]
      }
      emitir_evento: {
        Args: {
          p_detalle?: Json
          p_ente: string
          p_evento: Database["public"]["Enums"]["tipo_evento"]
          p_registro_id: string
        }
        Returns: undefined
      }
      equipo_de: { Args: { p_usuario: string }; Returns: string }
      etiqueta_registro: {
        Args: { p_ente: string; p_id: string }
        Returns: string
      }
      fijar_delegables: {
        Args: { p_admin: string; p_submodulos: string[] }
        Returns: undefined
      }
      guardar_plantilla: {
        Args: {
          p_descripcion: string
          p_id: string
          p_nombre: string
          p_pasos: Json
        }
        Returns: string
      }
      mi_equipo: { Args: never; Returns: string }
      normalizar_telefono: { Args: { t: string }; Returns: string }
      notificaciones_actores: {
        Args: never
        Returns: {
          id: string
          nombre: string
        }[]
      }
      notificaciones_listar: {
        Args: { p_limite?: number }
        Returns: {
          actor: string
          created_at: string
          destino: string
          destino_id: string
          etiqueta: string
          id: string
          leida: boolean
          motivo: string
          tipo: Database["public"]["Enums"]["tipo_notificacion"]
        }[]
      }
      notificar: {
        Args: {
          p_actor_id: string
          p_entidad: string
          p_entidad_id: string
          p_tipo: Database["public"]["Enums"]["tipo_notificacion"]
          p_usuario_id: string
        }
        Returns: undefined
      }
      obras_a_cargo: { Args: { p_obra: string }; Returns: boolean }
      obras_a_cargo_de: {
        Args: { p_obra: string; p_usuario: string }
        Returns: boolean
      }
      obras_alta: {
        Args: {
          p_compra_estimada?: string
          p_direccion: string
          p_estado?: Database["public"]["Enums"]["estado_obra"]
          p_localidad?: string
          p_nombre: string
          p_notas?: string
          p_origen: Database["public"]["Enums"]["origen_obra"]
          p_quien_empresa?: string
          p_quien_nuevo_email?: string
          p_quien_nuevo_nombre?: string
          p_quien_nuevo_telefono?: string
          p_quien_nuevo_tipo?: string
          p_quien_persona?: string
          p_tipo: Database["public"]["Enums"]["tipo_obra"]
        }
        Returns: string
      }
      obras_buscar: {
        Args: { p_texto: string }
        Returns: {
          id: string
          subtitulo: string
          tipo: string
          titulo: string
        }[]
      }
      obras_desactivar: { Args: { p_obra: string }; Returns: undefined }
      obras_etiqueta: {
        Args: { p_id: string; p_tipo: string }
        Returns: string
      }
      obras_nombres: {
        Args: never
        Returns: {
          id: string
          nombre: string
        }[]
      }
      obras_puede_abrir: {
        Args: { p_id: string; p_tipo: string; p_usuario: string }
        Returns: boolean
      }
      obras_parecidas: {
        Args: { p_direccion: string; p_nombre: string; p_obra?: string }
        Returns: {
          direccion: string
          id: string
          nombre: string
          responsable: string
        }[]
      }
      obras_por_aprobar: {
        Args: never
        Returns: {
          antes: Json
          created_at: string
          direccion: string
          estado: Database["public"]["Enums"]["estado_obra"]
          guardados: Json
          id: string
          localidad: string
          nombre: string
          notas: string
          origen: Database["public"]["Enums"]["origen_obra"]
          parecidas: Json
          responsable: string
          tipo: Database["public"]["Enums"]["tipo_obra"]
        }[]
      }
      obras_resolver: {
        Args: {
          p_decision: string
          p_existente?: string
          p_motivo?: string
          p_obra: string
        }
        Returns: undefined
      }
      obras_puede_ver_obra: {
        Args: {
          p_activo: boolean
          p_equipo: string
          p_obra: string
          p_responsable: string
        }
        Returns: boolean
      }
      obras_puede_ver_obra_de: {
        Args: {
          p_activo: boolean
          p_equipo: string
          p_obra: string
          p_responsable: string
          p_usuario: string
        }
        Returns: boolean
      }
      obras_trabaja: { Args: { p_obra: string }; Returns: boolean }
      obras_trabaja_de: {
        Args: { p_obra: string; p_usuario: string }
        Returns: boolean
      }
      obras_transferir: {
        Args: { p_obra: string; p_quedarme?: boolean; p_responsable: string }
        Returns: undefined
      }
      puede_abrir_registro: {
        Args: { p_ente: string; p_id: string; p_usuario: string }
        Returns: boolean
      }
      puede_ver_relacion: {
        Args: {
          p_ente: string
          p_ente_rel: string
          p_id: string
          p_id_rel: string
        }
        Returns: boolean
      }
      quitar_delegador: {
        Args: {
          p_admin: string
          p_heredero: string | null
          p_no_copiar?: string[]
          p_saliente: string
        }
        Returns: undefined
      }
      tareas_actua_como_asignado: {
        Args: { p_actor: string; p_equipo: string; p_usuario: string }
        Returns: boolean
      }
      tareas_asignables: {
        Args: never
        Returns: {
          equipo_id: string
          nombre: string
          pedido: boolean
          puede_recibir: boolean
          usuario_id: string
        }[]
      }
      tareas_avisar_asignado: {
        Args: { p: Database["public"]["Tables"]["tareas"]["Row"] }
        Returns: undefined
      }
      tareas_avisar_huerfanos: {
        Args: { p_usuario: string }
        Returns: undefined
      }
      tareas_avisos_salida: {
        Args: never
        Returns: {
          notificacion_id: string
          titulo: string
        }[]
      }
      tareas_bloquea: { Args: { p_paso: string }; Returns: boolean }
      tareas_buscar: {
        Args: { p_texto: string }
        Returns: {
          id: string
          subtitulo: string
          tipo: string
          titulo: string
        }[]
      }
      tareas_cancelar_y_cerrar: {
        Args: { p_generar?: boolean; p_hilo: string; p_resultado?: string }
        Returns: undefined
      }
      tareas_completar_con_nota: {
        Args: { p_nota: string; p_resultado?: string; p_tarea: string }
        Returns: undefined
      }
      tareas_delegador_de: { Args: { p_equipo: string }; Returns: string }
      tareas_desactivar_hilo: { Args: { p_hilo: string }; Returns: undefined }
      tareas_desactivar_paso: { Args: { p_paso: string }; Returns: undefined }
      tareas_destinatario: {
        Args: { p_equipo: string; p_usuario: string }
        Returns: string
      }
      tareas_entregar: { Args: { p_usuario: string }; Returns: undefined }
      tareas_equipo_de_asignado: {
        Args: { p_equipo: string; p_usuario: string }
        Returns: string
      }
      tareas_es_pedido: {
        Args: { p_equipo: string; p_responsable: string; p_usuario: string }
        Returns: boolean
      }
      tareas_estado_al_abrir: {
        Args: {
          p_directo: boolean
          p_equipo: string
          p_responsable: string
          p_usuario: string
        }
        Returns: Database["public"]["Enums"]["estado_tarea"]
      }
      tareas_etiqueta: {
        Args: { p_id: string; p_tipo: string }
        Returns: string
      }
      tareas_hoy: { Args: never; Returns: string }
      tareas_insertar_antes: {
        Args: {
          p_asignado_equipo_id: string
          p_asignado_id: string
          p_descripcion: string
          p_prioridad?: Database["public"]["Enums"]["prioridad_tarea"]
          p_siguiente: string
          p_titulo: string
          p_vence?: string
          p_vence_dias?: number
        }
        Returns: string
      }
      tareas_nombres: {
        Args: never
        Returns: {
          id: string
          nombre: string
        }[]
      }
      tareas_puede_recibir: {
        Args: { p_equipo: string; p_usuario: string }
        Returns: boolean
      }
      tareas_puede_ver_hilo: {
        Args: {
          p_activo: boolean
          p_equipo: string
          p_hilo: string
          p_responsable: string
        }
        Returns: boolean
      }
      tareas_puede_ver_hilo_de: {
        Args: {
          p_activo: boolean
          p_equipo: string
          p_hilo: string
          p_responsable: string
          p_usuario: string
        }
        Returns: boolean
      }
      tareas_puede_ver_tarea: {
        Args: { p_activo: boolean; p_hilo: string }
        Returns: boolean
      }
      tareas_puede_ver_tarea_de: {
        Args: { p_activo: boolean; p_hilo: string; p_usuario: string }
        Returns: boolean
      }
      tareas_referencias: {
        Args: { p_texto: string }
        Returns: {
          ente: string
          registro_id: string
        }[]
      }
      tareas_siguiente_efectivo: { Args: { p_paso: string }; Returns: string }
      tareas_transferir_hilo: {
        Args: { p_hilo: string; p_responsable: string }
        Returns: undefined
      }
      tiene_permiso: { Args: { p_codigo: string }; Returns: boolean }
      trabaja_registro: {
        Args: { p_ente: string; p_id: string }
        Returns: boolean
      }
      usar_plantilla: {
        Args: {
          p_asignados?: Json
          p_hilo?: string
          p_plantilla: string
          p_titulo?: string
        }
        Returns: string
      }
      usuario_tiene_permiso: {
        Args: { p_codigo: string; p_usuario: string }
        Returns: boolean
      }
      usuarios_con_permiso: {
        Args: { p_codigo: string }
        Returns: {
          id: string
          nombre: string
        }[]
      }
    }
    Enums: {
      estado_hilo: "abierto" | "cerrado"
      estado_obra:
        | "idea"
        | "en_busqueda"
        | "en_cotizacion"
        | "contratada"
        | "perdida"
      estado_tarea:
        | "solicitada"
        | "pendiente"
        | "rechazada"
        | "completada"
        | "cancelada"
      motivo_perdida:
        | "precio"
        | "plazo"
        | "producto"
        | "proveedor_habitual"
        | "obra_suspendida"
        | "sin_respuesta"
        | "otro"
      origen_obra:
        | "referente"
        | "cartel"
        | "web_redes"
        | "cliente_anterior"
        | "llamado"
        | "otro"
      prioridad_tarea: "baja" | "media" | "alta"
      recurrencia_unidad: "dia" | "mes"
      tipo_evento:
        | "alta"
        | "baja"
        | "reactivacion"
        | "estado"
        | "relacion_alta"
        | "relacion_baja"
        | "transferencia"
      tipo_notificacion:
        | "miembro_nuevo"
        | "permiso_otorgado"
        | "delegador_designado"
        | "tarea_asignada"
        | "pedido_recibido"
        | "paso_editado"
        | "pedido_aceptado"
        | "pedido_rechazado"
        | "paso_reabierto"
        | "hilo_transferido"
        | "paso_habilitado"
        | "paso_bloqueado"
        | "paso_reasignado"
        | "paso_quitado"
        | "paso_a_reasignar"
        | "paso_sumado"
        | "paso_huerfano"
        | "hilos_huerfanos"
        | "hilo_dado_de_baja"
        | "paso_dado_de_baja"
        | "paso_completado"
        | "paso_cancelado"
        | "obra_transferida"
        | "obra_sumado"
        | "obra_quitado"
        | "obras_recibidas"
        | "obras_huerfanas"
        | "persona_transferida"
        | "agenda_recibida"
        | "personas_huerfanas"
        | "alta_por_aprobar"
        | "alta_aprobada"
        | "alta_rechazada"
        | "alta_es_la_misma"
        | "obra_misma_sumado"
      tipo_obra:
        | "edificio_residencial"
        | "casa"
        | "oficinas_comercial"
        | "industrial"
        | "otro"
      tipo_regla_submodulo: "requiere" | "excluye"
      tipo_submodulo: "vista" | "funcion"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      estado_hilo: ["abierto", "cerrado"],
      estado_obra: [
        "idea",
        "en_busqueda",
        "en_cotizacion",
        "contratada",
        "perdida",
      ],
      estado_tarea: [
        "solicitada",
        "pendiente",
        "rechazada",
        "completada",
        "cancelada",
      ],
      motivo_perdida: [
        "precio",
        "plazo",
        "producto",
        "proveedor_habitual",
        "obra_suspendida",
        "sin_respuesta",
        "otro",
      ],
      origen_obra: [
        "referente",
        "cartel",
        "web_redes",
        "cliente_anterior",
        "llamado",
        "otro",
      ],
      prioridad_tarea: ["baja", "media", "alta"],
      recurrencia_unidad: ["dia", "mes"],
      tipo_evento: [
        "alta",
        "baja",
        "reactivacion",
        "estado",
        "relacion_alta",
        "relacion_baja",
        "transferencia",
      ],
      tipo_notificacion: [
        "miembro_nuevo",
        "permiso_otorgado",
        "delegador_designado",
        "tarea_asignada",
        "pedido_recibido",
        "paso_editado",
        "pedido_aceptado",
        "pedido_rechazado",
        "paso_reabierto",
        "hilo_transferido",
        "paso_habilitado",
        "paso_bloqueado",
        "paso_reasignado",
        "paso_quitado",
        "paso_a_reasignar",
        "paso_sumado",
        "paso_huerfano",
        "hilos_huerfanos",
        "hilo_dado_de_baja",
        "paso_dado_de_baja",
        "paso_completado",
        "paso_cancelado",
        "obra_transferida",
        "obra_sumado",
        "obra_quitado",
        "obras_recibidas",
        "obras_huerfanas",
        "persona_transferida",
        "agenda_recibida",
        "personas_huerfanas",
        "alta_por_aprobar",
        "alta_aprobada",
        "alta_rechazada",
        "alta_es_la_misma",
        "obra_misma_sumado",
      ],
      tipo_obra: [
        "edificio_residencial",
        "casa",
        "oficinas_comercial",
        "industrial",
        "otro",
      ],
      tipo_regla_submodulo: ["requiere", "excluye"],
      tipo_submodulo: ["vista", "funcion"],
    },
  },
} as const
