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
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      airlines: {
        Row: {
          active: boolean
          callsign: string | null
          country: string | null
          iata: string
          icao: string | null
          name: string
        }
        Insert: {
          active: boolean
          callsign?: string | null
          country?: string | null
          iata: string
          icao?: string | null
          name: string
        }
        Update: {
          active?: boolean
          callsign?: string | null
          country?: string | null
          iata?: string
          icao?: string | null
          name?: string
        }
        Relationships: []
      }
      airports: {
        Row: {
          city: string | null
          country: string | null
          elevation_ft: number | null
          iata: string
          icao: string | null
          latitude: number
          longitude: number
          name: string
          timezone: string | null
        }
        Insert: {
          city?: string | null
          country?: string | null
          elevation_ft?: number | null
          iata: string
          icao?: string | null
          latitude: number
          longitude: number
          name: string
          timezone?: string | null
        }
        Update: {
          city?: string | null
          country?: string | null
          elevation_ft?: number | null
          iata?: string
          icao?: string | null
          latitude?: number
          longitude?: number
          name?: string
          timezone?: string | null
        }
        Relationships: []
      }
      connection_requests: {
        Row: {
          created_at: string
          id: string
          invite_code: string
          inviter_id: string
          requester_id: string
          responded_at: string | null
          status: string
        }
        Insert: {
          created_at?: string
          id?: string
          invite_code: string
          inviter_id: string
          requester_id: string
          responded_at?: string | null
          status?: string
        }
        Update: {
          created_at?: string
          id?: string
          invite_code?: string
          inviter_id?: string
          requester_id?: string
          responded_at?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "connection_requests_invite_code_fkey"
            columns: ["invite_code"]
            isOneToOne: false
            referencedRelation: "invite_codes"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "connection_requests_inviter_id_fkey"
            columns: ["inviter_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "connection_requests_requester_id_fkey"
            columns: ["requester_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      couples: {
        Row: {
          created_at: string
          dissolved_at: string | null
          dissolved_by: string | null
          id: string
          max_distance_km: number | null
          partner_a_id: string
          partner_b_id: string
          started_dating_on: string | null
          status: Database["public"]["Enums"]["couple_status"]
          updated_at: string
        }
        Insert: {
          created_at?: string
          dissolved_at?: string | null
          dissolved_by?: string | null
          id?: string
          max_distance_km?: number | null
          partner_a_id: string
          partner_b_id: string
          started_dating_on?: string | null
          status?: Database["public"]["Enums"]["couple_status"]
          updated_at?: string
        }
        Update: {
          created_at?: string
          dissolved_at?: string | null
          dissolved_by?: string | null
          id?: string
          max_distance_km?: number | null
          partner_a_id?: string
          partner_b_id?: string
          started_dating_on?: string | null
          status?: Database["public"]["Enums"]["couple_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "couples_dissolved_by_fkey"
            columns: ["dissolved_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "couples_partner_a_id_fkey"
            columns: ["partner_a_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "couples_partner_b_id_fkey"
            columns: ["partner_b_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      daily_streaks: {
        Row: {
          couple_id: string
          current_streak: number
          last_answered_day_index: number | null
          longest_streak: number
          updated_at: string
        }
        Insert: {
          couple_id: string
          current_streak?: number
          last_answered_day_index?: number | null
          longest_streak?: number
          updated_at?: string
        }
        Update: {
          couple_id?: string
          current_streak?: number
          last_answered_day_index?: number | null
          longest_streak?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "daily_streaks_couple_id_fkey"
            columns: ["couple_id"]
            isOneToOne: true
            referencedRelation: "couples"
            referencedColumns: ["id"]
          },
        ]
      }
      deep_conversation_topics: {
        Row: {
          active: boolean
          category: string
          deck_id: string | null
          id: string
          tier: string
          topic: string
        }
        Insert: {
          active?: boolean
          category: string
          deck_id?: string | null
          id?: string
          tier?: string
          topic: string
        }
        Update: {
          active?: boolean
          category?: string
          deck_id?: string | null
          id?: string
          tier?: string
          topic?: string
        }
        Relationships: [
          {
            foreignKeyName: "discussion_topics_deck_id_fkey"
            columns: ["deck_id"]
            isOneToOne: false
            referencedRelation: "game_decks"
            referencedColumns: ["id"]
          },
        ]
      }
      developer_updates: {
        Row: {
          author_id: string | null
          body: string
          created_at: string
          feature_id: string
          id: string
        }
        Insert: {
          author_id?: string | null
          body: string
          created_at?: string
          feature_id: string
          id?: string
        }
        Update: {
          author_id?: string | null
          body?: string
          created_at?: string
          feature_id?: string
          id?: string
        }
        Relationships: [
          {
            foreignKeyName: "developer_updates_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "developer_updates_feature_id_fkey"
            columns: ["feature_id"]
            isOneToOne: false
            referencedRelation: "feature_requests"
            referencedColumns: ["id"]
          },
        ]
      }
      device_push_tokens: {
        Row: {
          apns_token: string
          created_at: string
          environment: string
          id: string
          last_seen_at: string
          profile_id: string
        }
        Insert: {
          apns_token: string
          created_at?: string
          environment?: string
          id?: string
          last_seen_at?: string
          profile_id: string
        }
        Update: {
          apns_token?: string
          created_at?: string
          environment?: string
          id?: string
          last_seen_at?: string
          profile_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "device_push_tokens_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      feature_bookmarks: {
        Row: {
          created_at: string
          feature_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          feature_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          feature_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "feature_bookmarks_feature_id_fkey"
            columns: ["feature_id"]
            isOneToOne: false
            referencedRelation: "feature_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feature_bookmarks_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      feature_comments: {
        Row: {
          body: string
          created_at: string
          feature_id: string
          id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          body: string
          created_at?: string
          feature_id: string
          id?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          body?: string
          created_at?: string
          feature_id?: string
          id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "feature_comments_feature_id_fkey"
            columns: ["feature_id"]
            isOneToOne: false
            referencedRelation: "feature_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feature_comments_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      feature_notification_outbox: {
        Row: {
          created_at: string
          event_type: string
          feature_id: string
          id: string
          payload: Json
          processed_at: string | null
          recipient_id: string
        }
        Insert: {
          created_at?: string
          event_type: string
          feature_id: string
          id?: string
          payload: Json
          processed_at?: string | null
          recipient_id: string
        }
        Update: {
          created_at?: string
          event_type?: string
          feature_id?: string
          id?: string
          payload?: Json
          processed_at?: string | null
          recipient_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "feature_notification_outbox_feature_id_fkey"
            columns: ["feature_id"]
            isOneToOne: false
            referencedRelation: "feature_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feature_notification_outbox_recipient_id_fkey"
            columns: ["recipient_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      feature_requests: {
        Row: {
          author_id: string | null
          category: Database["public"]["Enums"]["feedback_request_category"]
          comment_count: number
          created_at: string
          description: string
          id: string
          is_pinned: boolean
          merged_into: string | null
          slug: string
          status: Database["public"]["Enums"]["feedback_request_status"]
          title: string
          updated_at: string
          upvote_count: number
        }
        Insert: {
          author_id?: string | null
          category: Database["public"]["Enums"]["feedback_request_category"]
          comment_count?: number
          created_at?: string
          description?: string
          id?: string
          is_pinned?: boolean
          merged_into?: string | null
          slug: string
          status?: Database["public"]["Enums"]["feedback_request_status"]
          title: string
          updated_at?: string
          upvote_count?: number
        }
        Update: {
          author_id?: string | null
          category?: Database["public"]["Enums"]["feedback_request_category"]
          comment_count?: number
          created_at?: string
          description?: string
          id?: string
          is_pinned?: boolean
          merged_into?: string | null
          slug?: string
          status?: Database["public"]["Enums"]["feedback_request_status"]
          title?: string
          updated_at?: string
          upvote_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "feature_requests_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feature_requests_merged_into_fkey"
            columns: ["merged_into"]
            isOneToOne: false
            referencedRelation: "feature_requests"
            referencedColumns: ["id"]
          },
        ]
      }
      feature_subscribers: {
        Row: {
          created_at: string
          feature_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          feature_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          feature_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "feature_subscribers_feature_id_fkey"
            columns: ["feature_id"]
            isOneToOne: false
            referencedRelation: "feature_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feature_subscribers_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      feature_votes: {
        Row: {
          created_at: string
          feature_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          feature_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          feature_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "feature_votes_feature_id_fkey"
            columns: ["feature_id"]
            isOneToOne: false
            referencedRelation: "feature_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feature_votes_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      feedback_admins: {
        Row: {
          created_at: string
          profile_id: string
        }
        Insert: {
          created_at?: string
          profile_id: string
        }
        Update: {
          created_at?: string
          profile_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "feedback_admins_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      flight_delay_stats: {
        Row: {
          average_late_minutes: number
          cancelled_percent: number
          computed_at: string
          diverted_percent: number
          early_percent: number
          ident: string
          late_15_percent: number
          late_30_percent: number
          late_45_percent: number
          late_percent: number
          observed_count: number
          on_time_percent: number
        }
        Insert: {
          average_late_minutes: number
          cancelled_percent: number
          computed_at?: string
          diverted_percent: number
          early_percent: number
          ident: string
          late_15_percent: number
          late_30_percent: number
          late_45_percent: number
          late_percent: number
          observed_count: number
          on_time_percent: number
        }
        Update: {
          average_late_minutes?: number
          cancelled_percent?: number
          computed_at?: string
          diverted_percent?: number
          early_percent?: number
          ident?: string
          late_15_percent?: number
          late_30_percent?: number
          late_45_percent?: number
          late_percent?: number
          observed_count?: number
          on_time_percent?: number
        }
        Relationships: []
      }
      flight_documents: {
        Row: {
          content_type: string | null
          created_at: string
          doc_type: string
          file_path: string
          flight_id: string | null
          id: string
          original_filename: string | null
          trip_id: string | null
          uploaded_by: string
        }
        Insert: {
          content_type?: string | null
          created_at?: string
          doc_type?: string
          file_path: string
          flight_id?: string | null
          id?: string
          original_filename?: string | null
          trip_id?: string | null
          uploaded_by: string
        }
        Update: {
          content_type?: string | null
          created_at?: string
          doc_type?: string
          file_path?: string
          flight_id?: string | null
          id?: string
          original_filename?: string | null
          trip_id?: string | null
          uploaded_by?: string
        }
        Relationships: [
          {
            foreignKeyName: "flight_documents_flight_id_fkey"
            columns: ["flight_id"]
            isOneToOne: false
            referencedRelation: "flights"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "flight_documents_trip_id_fkey"
            columns: ["trip_id"]
            isOneToOne: false
            referencedRelation: "trips"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "flight_documents_uploaded_by_fkey"
            columns: ["uploaded_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      flight_live_positions: {
        Row: {
          altitude: number | null
          atc_ident: string | null
          consecutive_failures: number
          fa_flight_id: string
          fetched_at: string | null
          groundspeed: number | null
          heading: number | null
          hex: string | null
          latitude: number | null
          longitude: number | null
          query_key: string | null
          source: string | null
          updated_at: string
        }
        Insert: {
          altitude?: number | null
          atc_ident?: string | null
          consecutive_failures?: number
          fa_flight_id: string
          fetched_at?: string | null
          groundspeed?: number | null
          heading?: number | null
          hex?: string | null
          latitude?: number | null
          longitude?: number | null
          query_key?: string | null
          source?: string | null
          updated_at?: string
        }
        Update: {
          altitude?: number | null
          atc_ident?: string | null
          consecutive_failures?: number
          fa_flight_id?: string
          fetched_at?: string | null
          groundspeed?: number | null
          heading?: number | null
          hex?: string | null
          latitude?: number | null
          longitude?: number | null
          query_key?: string | null
          source?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      flight_notification_preferences: {
        Row: {
          arrival_at_gate: boolean
          baggage_claim_update: boolean
          created_at: string
          delay_or_cancellation: boolean
          departure: boolean
          flight_id: string
          gate_terminal_changes: boolean
          id: string
          landing: boolean
          profile_id: string
          updated_at: string
        }
        Insert: {
          arrival_at_gate?: boolean
          baggage_claim_update?: boolean
          created_at?: string
          delay_or_cancellation?: boolean
          departure?: boolean
          flight_id: string
          gate_terminal_changes?: boolean
          id?: string
          landing?: boolean
          profile_id: string
          updated_at?: string
        }
        Update: {
          arrival_at_gate?: boolean
          baggage_claim_update?: boolean
          created_at?: string
          delay_or_cancellation?: boolean
          departure?: boolean
          flight_id?: string
          gate_terminal_changes?: boolean
          id?: string
          landing?: boolean
          profile_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "flight_notification_preferences_flight_id_fkey"
            columns: ["flight_id"]
            isOneToOne: false
            referencedRelation: "flights"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "flight_notification_preferences_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      flight_status_events: {
        Row: {
          created_at: string
          flight_id: string
          id: string
          new_value: string | null
          occurred_at: string
          previous_value: string | null
          source: string
          type: Database["public"]["Enums"]["flight_status_event_type"]
        }
        Insert: {
          created_at?: string
          flight_id: string
          id?: string
          new_value?: string | null
          occurred_at?: string
          previous_value?: string | null
          source?: string
          type: Database["public"]["Enums"]["flight_status_event_type"]
        }
        Update: {
          created_at?: string
          flight_id?: string
          id?: string
          new_value?: string | null
          occurred_at?: string
          previous_value?: string | null
          source?: string
          type?: Database["public"]["Enums"]["flight_status_event_type"]
        }
        Relationships: [
          {
            foreignKeyName: "flight_status_events_flight_id_fkey"
            columns: ["flight_id"]
            isOneToOne: false
            referencedRelation: "flights"
            referencedColumns: ["id"]
          },
        ]
      }
      flight_updates: {
        Row: {
          created_at: string
          created_by: string
          flight_id: string
          id: string
          kind: Database["public"]["Enums"]["flight_update_kind"]
          note: string | null
        }
        Insert: {
          created_at?: string
          created_by: string
          flight_id: string
          id?: string
          kind: Database["public"]["Enums"]["flight_update_kind"]
          note?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string
          flight_id?: string
          id?: string
          kind?: Database["public"]["Enums"]["flight_update_kind"]
          note?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "flight_updates_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "flight_updates_flight_id_fkey"
            columns: ["flight_id"]
            isOneToOne: false
            referencedRelation: "flights"
            referencedColumns: ["id"]
          },
        ]
      }
      flights: {
        Row: {
          actual_in: string | null
          actual_off: string | null
          actual_on: string | null
          actual_out: string | null
          aircraft_type: string | null
          airline_code: string | null
          airline_logo_url: string | null
          airline_name: string | null
          arrival_delay_seconds: number | null
          atc_ident: string | null
          baggage_claim: string | null
          cancelled: boolean
          couple_id: string
          created_at: string
          created_by: string | null
          departure_delay_seconds: number | null
          destination_city: string | null
          destination_iata: string | null
          destination_icao: string | null
          destination_latitude: number | null
          destination_longitude: number | null
          destination_name: string | null
          destination_timezone: string | null
          diverted: boolean
          estimated_in: string | null
          estimated_off: string | null
          estimated_on: string | null
          estimated_out: string | null
          fa_flight_id: string | null
          flight_number_iata: string | null
          flight_number_icao: string | null
          gate_destination: string | null
          gate_origin: string | null
          id: string
          last_refreshed_at: string | null
          origin_city: string | null
          origin_iata: string | null
          origin_icao: string | null
          origin_latitude: number | null
          origin_longitude: number | null
          origin_name: string | null
          origin_timezone: string | null
          position_altitude: number | null
          position_groundspeed: number | null
          position_heading: number | null
          position_latitude: number | null
          position_longitude: number | null
          position_updated_at: string | null
          pre_departure_notified: boolean
          registration: string | null
          route: string | null
          scheduled_in: string | null
          scheduled_off: string | null
          scheduled_on: string | null
          scheduled_out: string | null
          shared: boolean
          status: string
          terminal_destination: string | null
          terminal_origin: string | null
          tracking_enabled: boolean
          traveler_ids: string[]
          trip_id: string | null
          updated_at: string
          weather_destination: Json | null
          weather_origin: Json | null
          weather_updated_at: string | null
        }
        Insert: {
          actual_in?: string | null
          actual_off?: string | null
          actual_on?: string | null
          actual_out?: string | null
          aircraft_type?: string | null
          airline_code?: string | null
          airline_logo_url?: string | null
          airline_name?: string | null
          arrival_delay_seconds?: number | null
          atc_ident?: string | null
          baggage_claim?: string | null
          cancelled?: boolean
          couple_id: string
          created_at?: string
          created_by?: string | null
          departure_delay_seconds?: number | null
          destination_city?: string | null
          destination_iata?: string | null
          destination_icao?: string | null
          destination_latitude?: number | null
          destination_longitude?: number | null
          destination_name?: string | null
          destination_timezone?: string | null
          diverted?: boolean
          estimated_in?: string | null
          estimated_off?: string | null
          estimated_on?: string | null
          estimated_out?: string | null
          fa_flight_id?: string | null
          flight_number_iata?: string | null
          flight_number_icao?: string | null
          gate_destination?: string | null
          gate_origin?: string | null
          id?: string
          last_refreshed_at?: string | null
          origin_city?: string | null
          origin_iata?: string | null
          origin_icao?: string | null
          origin_latitude?: number | null
          origin_longitude?: number | null
          origin_name?: string | null
          origin_timezone?: string | null
          position_altitude?: number | null
          position_groundspeed?: number | null
          position_heading?: number | null
          position_latitude?: number | null
          position_longitude?: number | null
          position_updated_at?: string | null
          pre_departure_notified?: boolean
          registration?: string | null
          route?: string | null
          scheduled_in?: string | null
          scheduled_off?: string | null
          scheduled_on?: string | null
          scheduled_out?: string | null
          shared?: boolean
          status?: string
          terminal_destination?: string | null
          terminal_origin?: string | null
          tracking_enabled?: boolean
          traveler_ids?: string[]
          trip_id?: string | null
          updated_at?: string
          weather_destination?: Json | null
          weather_origin?: Json | null
          weather_updated_at?: string | null
        }
        Update: {
          actual_in?: string | null
          actual_off?: string | null
          actual_on?: string | null
          actual_out?: string | null
          aircraft_type?: string | null
          airline_code?: string | null
          airline_logo_url?: string | null
          airline_name?: string | null
          arrival_delay_seconds?: number | null
          atc_ident?: string | null
          baggage_claim?: string | null
          cancelled?: boolean
          couple_id?: string
          created_at?: string
          created_by?: string | null
          departure_delay_seconds?: number | null
          destination_city?: string | null
          destination_iata?: string | null
          destination_icao?: string | null
          destination_latitude?: number | null
          destination_longitude?: number | null
          destination_name?: string | null
          destination_timezone?: string | null
          diverted?: boolean
          estimated_in?: string | null
          estimated_off?: string | null
          estimated_on?: string | null
          estimated_out?: string | null
          fa_flight_id?: string | null
          flight_number_iata?: string | null
          flight_number_icao?: string | null
          gate_destination?: string | null
          gate_origin?: string | null
          id?: string
          last_refreshed_at?: string | null
          origin_city?: string | null
          origin_iata?: string | null
          origin_icao?: string | null
          origin_latitude?: number | null
          origin_longitude?: number | null
          origin_name?: string | null
          origin_timezone?: string | null
          position_altitude?: number | null
          position_groundspeed?: number | null
          position_heading?: number | null
          position_latitude?: number | null
          position_longitude?: number | null
          position_updated_at?: string | null
          pre_departure_notified?: boolean
          registration?: string | null
          route?: string | null
          scheduled_in?: string | null
          scheduled_off?: string | null
          scheduled_on?: string | null
          scheduled_out?: string | null
          shared?: boolean
          status?: string
          terminal_destination?: string | null
          terminal_origin?: string | null
          tracking_enabled?: boolean
          traveler_ids?: string[]
          trip_id?: string | null
          updated_at?: string
          weather_destination?: Json | null
          weather_origin?: Json | null
          weather_updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "flights_couple_id_fkey"
            columns: ["couple_id"]
            isOneToOne: false
            referencedRelation: "couples"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "flights_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "flights_trip_id_fkey"
            columns: ["trip_id"]
            isOneToOne: false
            referencedRelation: "trips"
            referencedColumns: ["id"]
          },
        ]
      }
      game_content_duplicate_dismissals: {
        Row: {
          content_type: string
          created_at: string
          dismissed_by: string | null
          id: string
          row_a_id: string
          row_b_id: string
        }
        Insert: {
          content_type: string
          created_at?: string
          dismissed_by?: string | null
          id?: string
          row_a_id: string
          row_b_id: string
        }
        Update: {
          content_type?: string
          created_at?: string
          dismissed_by?: string | null
          id?: string
          row_a_id?: string
          row_b_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "game_content_duplicate_dismissals_dismissed_by_fkey"
            columns: ["dismissed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      game_decks: {
        Row: {
          active: boolean
          emoji: string
          game_type: Database["public"]["Enums"]["game_type"]
          id: string
          question_count: number
          sort_order: number
          tier: string
          title: string
          topic: string
        }
        Insert: {
          active?: boolean
          emoji: string
          game_type: Database["public"]["Enums"]["game_type"]
          id?: string
          question_count?: number
          sort_order?: number
          tier?: string
          title: string
          topic: string
        }
        Update: {
          active?: boolean
          emoji?: string
          game_type?: Database["public"]["Enums"]["game_type"]
          id?: string
          question_count?: number
          sort_order?: number
          tier?: string
          title?: string
          topic?: string
        }
        Relationships: []
      }
      game_responses: {
        Row: {
          answer: Json
          created_at: string
          id: string
          is_correct: boolean | null
          responder_id: string
          round_number: number
          session_id: string
        }
        Insert: {
          answer: Json
          created_at?: string
          id?: string
          is_correct?: boolean | null
          responder_id: string
          round_number: number
          session_id: string
        }
        Update: {
          answer?: Json
          created_at?: string
          id?: string
          is_correct?: boolean | null
          responder_id?: string
          round_number?: number
          session_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "game_responses_responder_id_fkey"
            columns: ["responder_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "game_responses_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "game_sessions"
            referencedColumns: ["id"]
          },
        ]
      }
      game_session_rounds: {
        Row: {
          content_id: string
          discussion_status: string | null
          id: string
          round_number: number
          session_id: string
        }
        Insert: {
          content_id: string
          discussion_status?: string | null
          id?: string
          round_number: number
          session_id: string
        }
        Update: {
          content_id?: string
          discussion_status?: string | null
          id?: string
          round_number?: number
          session_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "game_session_rounds_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "game_sessions"
            referencedColumns: ["id"]
          },
        ]
      }
      game_sessions: {
        Row: {
          completed_at: string | null
          couple_id: string
          created_at: string
          deck_id: string | null
          game_type: Database["public"]["Enums"]["game_type"]
          id: string
          initiator_id: string
          is_daily: boolean
          started_at: string | null
          status: Database["public"]["Enums"]["game_status"]
          total_rounds: number
          updated_at: string
        }
        Insert: {
          completed_at?: string | null
          couple_id: string
          created_at?: string
          deck_id?: string | null
          game_type: Database["public"]["Enums"]["game_type"]
          id?: string
          initiator_id: string
          is_daily?: boolean
          started_at?: string | null
          status?: Database["public"]["Enums"]["game_status"]
          total_rounds?: number
          updated_at?: string
        }
        Update: {
          completed_at?: string | null
          couple_id?: string
          created_at?: string
          deck_id?: string | null
          game_type?: Database["public"]["Enums"]["game_type"]
          id?: string
          initiator_id?: string
          is_daily?: boolean
          started_at?: string | null
          status?: Database["public"]["Enums"]["game_status"]
          total_rounds?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "game_sessions_couple_id_fkey"
            columns: ["couple_id"]
            isOneToOne: false
            referencedRelation: "couples"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "game_sessions_deck_id_fkey"
            columns: ["deck_id"]
            isOneToOne: false
            referencedRelation: "game_decks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "game_sessions_initiator_id_fkey"
            columns: ["initiator_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      invite_codes: {
        Row: {
          code: string
          couple_id: string | null
          created_at: string
          expires_at: string
          inviter_id: string
          name_lookup_count: number
          redeemed_at: string | null
          status: Database["public"]["Enums"]["invite_status"]
        }
        Insert: {
          code: string
          couple_id?: string | null
          created_at?: string
          expires_at?: string
          inviter_id: string
          name_lookup_count?: number
          redeemed_at?: string | null
          status?: Database["public"]["Enums"]["invite_status"]
        }
        Update: {
          code?: string
          couple_id?: string | null
          created_at?: string
          expires_at?: string
          inviter_id?: string
          name_lookup_count?: number
          redeemed_at?: string | null
          status?: Database["public"]["Enums"]["invite_status"]
        }
        Relationships: [
          {
            foreignKeyName: "invite_codes_couple_id_fkey"
            columns: ["couple_id"]
            isOneToOne: false
            referencedRelation: "couples"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invite_codes_inviter_id_fkey"
            columns: ["inviter_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      invite_redemption_attempts: {
        Row: {
          attempted_at: string
          id: string
          redeemer_id: string
        }
        Insert: {
          attempted_at?: string
          id?: string
          redeemer_id: string
        }
        Update: {
          attempted_at?: string
          id?: string
          redeemer_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "invite_redemption_attempts_redeemer_id_fkey"
            columns: ["redeemer_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      live_activity_push_tokens: {
        Row: {
          activity_id: string
          created_at: string
          environment: string
          flight_id: string
          id: string
          profile_id: string
          push_token: string
          updated_at: string
        }
        Insert: {
          activity_id: string
          created_at?: string
          environment?: string
          flight_id: string
          id?: string
          profile_id: string
          push_token: string
          updated_at?: string
        }
        Update: {
          activity_id?: string
          created_at?: string
          environment?: string
          flight_id?: string
          id?: string
          profile_id?: string
          push_token?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "live_activity_push_tokens_flight_id_fkey"
            columns: ["flight_id"]
            isOneToOne: false
            referencedRelation: "flights"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "live_activity_push_tokens_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      memories: {
        Row: {
          couple_id: string
          created_at: string
          id: string
          note: string
          occurred_at: string
          place_id: string | null
          title: string
          trip_id: string | null
        }
        Insert: {
          couple_id: string
          created_at?: string
          id?: string
          note?: string
          occurred_at?: string
          place_id?: string | null
          title: string
          trip_id?: string | null
        }
        Update: {
          couple_id?: string
          created_at?: string
          id?: string
          note?: string
          occurred_at?: string
          place_id?: string | null
          title?: string
          trip_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "memories_couple_id_fkey"
            columns: ["couple_id"]
            isOneToOne: false
            referencedRelation: "couples"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "memories_place_id_fkey"
            columns: ["place_id"]
            isOneToOne: false
            referencedRelation: "places"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "memories_trip_id_fkey"
            columns: ["trip_id"]
            isOneToOne: false
            referencedRelation: "trips"
            referencedColumns: ["id"]
          },
        ]
      }
      memory_photos: {
        Row: {
          created_at: string
          id: string
          memory_id: string
          photo_path: string
          position: number
        }
        Insert: {
          created_at?: string
          id?: string
          memory_id: string
          photo_path: string
          position?: number
        }
        Update: {
          created_at?: string
          id?: string
          memory_id?: string
          photo_path?: string
          position?: number
        }
        Relationships: [
          {
            foreignKeyName: "memory_photos_memory_id_fkey"
            columns: ["memory_id"]
            isOneToOne: false
            referencedRelation: "memories"
            referencedColumns: ["id"]
          },
        ]
      }
      more_likely_prompts: {
        Row: {
          active: boolean
          category: string
          deck_id: string | null
          id: string
          prompt: string
          tier: string
        }
        Insert: {
          active?: boolean
          category: string
          deck_id?: string | null
          id?: string
          prompt: string
          tier?: string
        }
        Update: {
          active?: boolean
          category?: string
          deck_id?: string | null
          id?: string
          prompt?: string
          tier?: string
        }
        Relationships: [
          {
            foreignKeyName: "more_likely_prompts_deck_id_fkey"
            columns: ["deck_id"]
            isOneToOne: false
            referencedRelation: "game_decks"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_preferences: {
        Row: {
          created_at: string
          daily_streak_reminder: boolean
          partner_drawing_saved: boolean
          partner_game_partner_finished: boolean
          partner_game_results_ready: boolean
          partner_game_started: boolean
          partner_invite_reminder: boolean
          partner_memory_added: boolean
          partner_trip_added: boolean
          profile_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          daily_streak_reminder?: boolean
          partner_drawing_saved?: boolean
          partner_game_partner_finished?: boolean
          partner_game_results_ready?: boolean
          partner_game_started?: boolean
          partner_invite_reminder?: boolean
          partner_memory_added?: boolean
          partner_trip_added?: boolean
          profile_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          daily_streak_reminder?: boolean
          partner_drawing_saved?: boolean
          partner_game_partner_finished?: boolean
          partner_game_results_ready?: boolean
          partner_game_started?: boolean
          partner_invite_reminder?: boolean
          partner_memory_added?: boolean
          partner_trip_added?: boolean
          profile_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "notification_preferences_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      places: {
        Row: {
          city: string
          country: string
          created_at: string
          iata_code: string | null
          id: string
          latitude: number
          longitude: number
          timezone: string | null
        }
        Insert: {
          city: string
          country: string
          created_at?: string
          iata_code?: string | null
          id?: string
          latitude: number
          longitude: number
          timezone?: string | null
        }
        Update: {
          city?: string
          country?: string
          created_at?: string
          iata_code?: string | null
          id?: string
          latitude?: number
          longitude?: number
          timezone?: string | null
        }
        Relationships: []
      }
      profiles: {
        Row: {
          accent_color_hex: string | null
          anniversary_date: string | null
          avatar_path: string | null
          created_at: string
          first_name: string
          home_place_id: string | null
          id: string
          partner_avatar_path: string | null
          partner_connected_celebration_shown: boolean
          partner_home_place_id: string | null
          partner_name: string | null
          setup_checklist_dismissed: boolean
          subscription_active: boolean
          subscription_checked_at: string | null
          subscription_tier: string | null
          updated_at: string
        }
        Insert: {
          accent_color_hex?: string | null
          anniversary_date?: string | null
          avatar_path?: string | null
          created_at?: string
          first_name?: string
          home_place_id?: string | null
          id: string
          partner_avatar_path?: string | null
          partner_connected_celebration_shown?: boolean
          partner_home_place_id?: string | null
          partner_name?: string | null
          setup_checklist_dismissed?: boolean
          subscription_active?: boolean
          subscription_checked_at?: string | null
          subscription_tier?: string | null
          updated_at?: string
        }
        Update: {
          accent_color_hex?: string | null
          anniversary_date?: string | null
          avatar_path?: string | null
          created_at?: string
          first_name?: string
          home_place_id?: string | null
          id?: string
          partner_avatar_path?: string | null
          partner_connected_celebration_shown?: boolean
          partner_home_place_id?: string | null
          partner_name?: string | null
          setup_checklist_dismissed?: boolean
          subscription_active?: boolean
          subscription_checked_at?: string | null
          subscription_tier?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "profiles_home_place_id_fkey"
            columns: ["home_place_id"]
            isOneToOne: false
            referencedRelation: "places"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profiles_partner_home_place_id_fkey"
            columns: ["partner_home_place_id"]
            isOneToOne: false
            referencedRelation: "places"
            referencedColumns: ["id"]
          },
        ]
      }
      this_or_that_prompts: {
        Row: {
          active: boolean
          category: string
          deck_id: string | null
          id: string
          option_a: string
          option_b: string
          tier: string
        }
        Insert: {
          active?: boolean
          category: string
          deck_id?: string | null
          id?: string
          option_a: string
          option_b: string
          tier?: string
        }
        Update: {
          active?: boolean
          category?: string
          deck_id?: string | null
          id?: string
          option_a?: string
          option_b?: string
          tier?: string
        }
        Relationships: [
          {
            foreignKeyName: "this_or_that_prompts_deck_id_fkey"
            columns: ["deck_id"]
            isOneToOne: false
            referencedRelation: "game_decks"
            referencedColumns: ["id"]
          },
        ]
      }
      trips: {
        Row: {
          arrival_at: string
          category: Database["public"]["Enums"]["trip_category"]
          couple_id: string
          created_at: string
          departure_at: string
          destination_id: string
          distance_km: number
          id: string
          notes: string | null
          origin_id: string
          traveler_ids: string[]
          updated_at: string
        }
        Insert: {
          arrival_at: string
          category: Database["public"]["Enums"]["trip_category"]
          couple_id: string
          created_at?: string
          departure_at: string
          destination_id: string
          distance_km?: number
          id?: string
          notes?: string | null
          origin_id: string
          traveler_ids?: string[]
          updated_at?: string
        }
        Update: {
          arrival_at?: string
          category?: Database["public"]["Enums"]["trip_category"]
          couple_id?: string
          created_at?: string
          departure_at?: string
          destination_id?: string
          distance_km?: number
          id?: string
          notes?: string | null
          origin_id?: string
          traveler_ids?: string[]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "trips_couple_id_fkey"
            columns: ["couple_id"]
            isOneToOne: false
            referencedRelation: "couples"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trips_destination_id_fkey"
            columns: ["destination_id"]
            isOneToOne: false
            referencedRelation: "places"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trips_origin_id_fkey"
            columns: ["origin_id"]
            isOneToOne: false
            referencedRelation: "places"
            referencedColumns: ["id"]
          },
        ]
      }
      trivia_questions: {
        Row: {
          active: boolean
          category: string
          correct_answer: string
          deck_id: string | null
          difficulty: string | null
          explanation: string | null
          id: string
          options: Json
          question: string
          tier: string
        }
        Insert: {
          active?: boolean
          category: string
          correct_answer: string
          deck_id?: string | null
          difficulty?: string | null
          explanation?: string | null
          id?: string
          options: Json
          question: string
          tier?: string
        }
        Update: {
          active?: boolean
          category?: string
          correct_answer?: string
          deck_id?: string | null
          difficulty?: string | null
          explanation?: string | null
          id?: string
          options?: Json
          question?: string
          tier?: string
        }
        Relationships: [
          {
            foreignKeyName: "trivia_questions_deck_id_fkey"
            columns: ["deck_id"]
            isOneToOne: false
            referencedRelation: "game_decks"
            referencedColumns: ["id"]
          },
        ]
      }
      waitlist_signups: {
        Row: {
          created_at: string
          email: string
          id: string
        }
        Insert: {
          created_at?: string
          email: string
          id?: string
        }
        Update: {
          created_at?: string
          email?: string
          id?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      abandon_game_session: {
        Args: { p_session_id: string }
        Returns: undefined
      }
      create_invite_code: {
        Args: never
        Returns: {
          code: string
          couple_id: string | null
          created_at: string
          expires_at: string
          inviter_id: string
          name_lookup_count: number
          redeemed_at: string | null
          status: Database["public"]["Enums"]["invite_status"]
        }
        SetofOptions: {
          from: "*"
          to: "invite_codes"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      delete_dissolved_couple_data: {
        Args: { p_couple_id: string }
        Returns: undefined
      }
      fetch_my_outgoing_connection_request: {
        Args: never
        Returns: {
          created_at: string
          id: string
          inviter_avatar_path: string
          inviter_first_name: string
          inviter_id: string
        }[]
      }
      fetch_pending_connection_requests: {
        Args: never
        Returns: {
          created_at: string
          id: string
          requester_avatar_path: string
          requester_first_name: string
          requester_id: string
        }[]
      }
      get_daily_question_session: { Args: never; Returns: string }
      get_daily_question_status: {
        Args: never
        Returns: {
          my_answered: boolean
          partner_answered: boolean
          session_id: string
        }[]
      }
      get_deck_progress: {
        Args: never
        Returns: {
          deck_id: string
          my_answered: number
          partner_answered: number
          session_id: string
          status: Database["public"]["Enums"]["game_status"]
          total_rounds: number
        }[]
      }
      get_feedback_public_profiles: {
        Args: { profile_ids: string[] }
        Returns: {
          avatar_path: string
          display_name: string
          id: string
        }[]
      }
      get_invite_code_inviter_info: {
        Args: { p_code: string }
        Returns: {
          avatar_path: string
          first_name: string
        }[]
      }
      is_couple_active: { Args: { target_couple_id: string }; Returns: boolean }
      is_couple_member: { Args: { target_couple_id: string }; Returns: boolean }
      is_feedback_admin: { Args: { check_id?: string }; Returns: boolean }
      leave_couple: {
        Args: { p_couple_id: string }
        Returns: {
          created_at: string
          dissolved_at: string | null
          dissolved_by: string | null
          id: string
          max_distance_km: number | null
          partner_a_id: string
          partner_b_id: string
          started_dating_on: string | null
          status: Database["public"]["Enums"]["couple_status"]
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "couples"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      mark_discussion_round: {
        Args: { p_round_id: string; p_status: string }
        Returns: undefined
      }
      merge_feature_requests: {
        Args: { source_id: string; target_id: string }
        Returns: undefined
      }
      popular_this_week: {
        Args: { result_limit?: number }
        Returns: {
          id: string
          recent_votes: number
          slug: string
          status: Database["public"]["Enums"]["feedback_request_status"]
          title: string
          upvote_count: number
        }[]
      }
      redeem_invite_code: {
        Args: { p_code: string }
        Returns: {
          created_at: string
          id: string
          invite_code: string
          inviter_id: string
          requester_id: string
          responded_at: string | null
          status: string
        }
        SetofOptions: {
          from: "*"
          to: "connection_requests"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      respond_to_connection_request: {
        Args: { p_accept: boolean; p_request_id: string }
        Returns: {
          created_at: string
          dissolved_at: string | null
          dissolved_by: string | null
          id: string
          max_distance_km: number | null
          partner_a_id: string
          partner_b_id: string
          started_dating_on: string | null
          status: Database["public"]["Enums"]["couple_status"]
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "couples"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      search_similar_feature_requests: {
        Args: { match_limit?: number; query: string }
        Returns: {
          id: string
          similarity: number
          slug: string
          status: Database["public"]["Enums"]["feedback_request_status"]
          title: string
          upvote_count: number
        }[]
      }
      show_limit: { Args: never; Returns: number }
      show_trgm: { Args: { "": string }; Returns: string[] }
      start_deck_session: { Args: { p_deck_id: string }; Returns: string }
      update_couple_anniversary_date: {
        Args: { p_couple_id: string; p_date: string }
        Returns: {
          created_at: string
          dissolved_at: string | null
          dissolved_by: string | null
          id: string
          max_distance_km: number | null
          partner_a_id: string
          partner_b_id: string
          started_dating_on: string | null
          status: Database["public"]["Enums"]["couple_status"]
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "couples"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      update_couple_max_distance: {
        Args: { p_couple_id: string; p_distance_km: number }
        Returns: undefined
      }
    }
    Enums: {
      couple_status: "active" | "dissolved"
      feedback_request_category:
        | "flights"
        | "memories"
        | "games"
        | "widgets"
        | "notifications"
        | "relationship"
        | "general"
      feedback_request_status:
        | "requested"
        | "considering"
        | "planned"
        | "in_progress"
        | "released"
        | "closed"
      flight_status_event_type:
        | "scheduled"
        | "delay"
        | "gate_change"
        | "terminal_change"
        | "departed"
        | "airborne"
        | "arrival_time_change"
        | "landed"
        | "arrived_at_gate"
        | "baggage_claim"
        | "cancelled"
        | "diverted"
      flight_update_kind:
        | "meal_service"
        | "disruption"
        | "going_to_sleep"
        | "custom"
      game_status:
        | "draft"
        | "active"
        | "waiting_for_partner"
        | "completed"
        | "abandoned"
        | "archived"
      game_type:
        | "trivia_battle"
        | "more_likely"
        | "this_or_that"
        | "deep_conversations"
      invite_status: "pending" | "redeemed" | "expired"
      trip_category: "seeing_each_other" | "together" | "personal"
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
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
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
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
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {
      couple_status: ["active", "dissolved"],
      feedback_request_category: [
        "flights",
        "memories",
        "games",
        "widgets",
        "notifications",
        "relationship",
        "general",
      ],
      feedback_request_status: [
        "requested",
        "considering",
        "planned",
        "in_progress",
        "released",
        "closed",
      ],
      flight_status_event_type: [
        "scheduled",
        "delay",
        "gate_change",
        "terminal_change",
        "departed",
        "airborne",
        "arrival_time_change",
        "landed",
        "arrived_at_gate",
        "baggage_claim",
        "cancelled",
        "diverted",
      ],
      flight_update_kind: [
        "meal_service",
        "disruption",
        "going_to_sleep",
        "custom",
      ],
      game_status: [
        "draft",
        "active",
        "waiting_for_partner",
        "completed",
        "abandoned",
        "archived",
      ],
      game_type: [
        "trivia_battle",
        "more_likely",
        "this_or_that",
        "deep_conversations",
      ],
      invite_status: ["pending", "redeemed", "expired"],
      trip_category: ["seeing_each_other", "together", "personal"],
    },
  },
} as const
