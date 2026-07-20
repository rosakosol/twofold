import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { useFeatureVoters } from "@/lib/queries/useFeatureVoters";

function avatarUrl(userId: string) {
  return `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/avatars/${userId}/avatar.jpg`;
}

export function VoterAvatarStack({ featureId, totalVotes }: { featureId: string; totalVotes: number }) {
  const { data: voters } = useFeatureVoters(featureId, totalVotes);

  if (!voters || voters.length === 0) return null;

  const overflow = totalVotes - voters.length;

  return (
    <div className="flex items-center">
      <div className="flex -space-x-2">
        {voters.map((voter) => (
          <Avatar key={voter.id} className="h-6 w-6 border-2 border-background">
            <AvatarImage src={avatarUrl(voter.id)} alt="" />
            <AvatarFallback className="text-[9px]">{voter.display_name.slice(0, 2).toUpperCase()}</AvatarFallback>
          </Avatar>
        ))}
      </div>
      {overflow > 0 && <span className="ml-2 text-xs text-muted-foreground">+{overflow} more</span>}
    </div>
  );
}
