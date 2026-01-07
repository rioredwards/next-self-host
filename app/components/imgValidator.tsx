"use client";

import Image from "next/image";
import { useState } from "react";
import { analyzeImageAction } from "../actions";
import type { AnalysisResult } from "../lib/imgValidatorTypes";

export default function ImgValidator() {
  const [file, setFile] = useState<File | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [result, setResult] = useState<AnalysisResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const selectedFile = e.target.files?.[0];
    if (selectedFile) {
      setFile(selectedFile);
      setResult(null);
      setError(null);

      // Create preview
      const reader = new FileReader();
      reader.onloadend = () => {
        setPreview(reader.result as string);
      };
      reader.readAsDataURL(selectedFile);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!file) return;

    setLoading(true);
    setError(null);

    try {
      const formData = new FormData();
      formData.append("file", file);

      const data = await analyzeImageAction(formData);
      setResult(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  };

  return (
    <main className="min-h-screen bg-gray-900 text-white p-8">
      <div className="max-w-4xl mx-auto">
        <h1 className="text-4xl font-bold mb-8 text-center">Image Analysis</h1>

        <form onSubmit={handleSubmit} className="mb-8">
          <div className="bg-gray-800 rounded-lg p-6">
            <label className="block mb-4">
              <span className="block mb-2 text-sm font-medium">Select Image</span>
              <input
                type="file"
                accept="image/*"
                onChange={handleFileChange}
                className="block w-full text-sm text-gray-300 file:mr-4 file:py-2 file:px-4 file:rounded-lg file:border-0 file:text-sm file:font-semibold file:bg-blue-600 file:text-white hover:file:bg-blue-700 cursor-pointer"
              />
            </label>

            <button
              type="submit"
              disabled={!file || loading}
              className="w-full bg-blue-600 hover:bg-blue-700 disabled:bg-gray-600 disabled:cursor-not-allowed text-white font-semibold py-3 px-6 rounded-lg transition">
              {loading ? "Analyzing..." : "Analyze Image"}
            </button>
          </div>
        </form>

        {error && (
          <div className="bg-red-900/50 border border-red-600 rounded-lg p-4 mb-6">
            <p className="text-red-200">{error}</p>
          </div>
        )}

        {preview && (
          <div className="bg-gray-800 rounded-lg p-6 mb-6">
            <h2 className="text-xl font-semibold mb-4">Preview</h2>
            <div className="flex justify-center">
              <Image
                width={100}
                height={100}
                src={preview}
                alt="Preview"
                className="max-w-full max-h-96 rounded-lg object-contain"
              />
            </div>
          </div>
        )}

        {result && (
          <div className="bg-gray-800 rounded-lg p-6">
            <h2 className="text-xl font-semibold mb-4">Analysis Results</h2>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              {/* NSFW Score */}
              <div className="space-y-2">
                <div className="flex justify-between items-center">
                  <span className="text-sm text-gray-400">NSFW Score</span>
                  <span
                    className={`font-semibold ${
                      result.is_nsfw ? "text-red-400" : "text-green-400"
                    }`}>
                    {result.nsfw_score.toFixed(4)}
                  </span>
                </div>
                <div className="w-full bg-gray-700 rounded-full h-2">
                  <div
                    className={`h-2 rounded-full transition-all ${
                      result.is_nsfw ? "bg-red-500" : "bg-gray-600"
                    }`}
                    style={{ width: `${result.nsfw_score * 100}%` }}
                  />
                </div>
                <div className="flex gap-2">
                  {result.is_nsfw ? (
                    <span className="px-3 py-1 bg-red-600 text-white rounded-full text-sm font-semibold">
                      NSFW
                    </span>
                  ) : (
                    <span className="px-3 py-1 bg-green-600 text-white rounded-full text-sm font-semibold">
                      SFW
                    </span>
                  )}
                </div>
              </div>

              {/* Dog Probability */}
              <div className="space-y-2">
                <div className="flex justify-between items-center">
                  <span className="text-sm text-gray-400">Dog Probability</span>
                  <span
                    className={`font-semibold ${
                      result.is_dog ? "text-green-400" : "text-gray-400"
                    }`}>
                    {result.dog_probability.toFixed(4)}
                  </span>
                </div>
                <div className="w-full bg-gray-700 rounded-full h-2">
                  <div
                    className={`h-2 rounded-full transition-all ${
                      result.is_dog ? "bg-green-500" : "bg-gray-600"
                    }`}
                    style={{ width: `${result.dog_probability * 100}%` }}
                  />
                </div>
                <div className="flex gap-2">
                  {result.is_dog && (
                    <span className="px-3 py-1 bg-green-600 text-white rounded-full text-sm font-semibold">
                      DOG
                    </span>
                  )}
                </div>
              </div>
            </div>
          </div>
        )}
      </div>
    </main>
  );
}
