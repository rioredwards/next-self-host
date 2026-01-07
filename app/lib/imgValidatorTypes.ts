export interface AnalysisResult {
  filename: string;
  nsfw_score: number;
  is_nsfw: boolean;
  dog_probability: number;
  is_dog: boolean;
}
