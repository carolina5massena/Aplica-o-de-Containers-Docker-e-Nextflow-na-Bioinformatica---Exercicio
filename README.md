# Nextflow RNA-Seq Analysis Pipeline

This pipeline processes RNA-Seq data, from raw sequence reads to feature counting, using various bioinformatics tools containerized with Docker.

## Prerequisites

- [Nextflow](https://www.nextflow.io/)
- [Docker](https://www.docker.com/)

## Pipeline Overview

The pipeline performs the following steps:

1. **Bowtie Index Building**: Builds a Bowtie index from the reference genome.
2. **UMI Extraction**: Extracts Unique Molecular Identifiers (UMIs) from raw sequence reads.
3. **Alignment**: Aligns sequence reads to the reference genome using Bowtie.
4. **SAM to BAM Conversion**: Converts SAM files to BAM format using Samtools.
5. **BAM Sorting**: Sorts BAM files using Samtools.
6. **BAM Indexing**: Indexes sorted BAM files using Samtools.
7. **Deduplication**: Deduplicates BAM files using UMI-tools.
8. **Feature Counting**: Counts features using featureCounts.
9. **Quality Control**: Performs quality control checks using FastQC.

## Configuration

### Nextflow Configuration (nextflow.config)

The following parameters and settings are defined in the `nextflow.config` file:

- **dag { overwrite = true }**: Ensures that the Directed Acyclic Graph (DAG) is overwritten if it already exists.
- **docker { enabled = true }**: Enables the use of Docker containers.
- **report.overwrite = true**: Overwrites the report file if it already exists.
- **timeline.overwrite = true**: Overwrites the timeline file if it already exists.
- **cleanup = true**: Cleans up intermediate files after the workflow execution.
- **workDir = "/mnt/d/Teste_Nextflow/work"**: Specifies the working directory for Nextflow.

### Pipeline Parameters

The following parameters can be set in the Nextflow script:

- `params.inputDir`: Directory containing the input files.
- `params.outputDir`: Directory where output files will be saved.
- `params.genome_path`: Path to the reference genome.
- `params.genome_gtf`: GTF file for the reference genome.
- `params.genoma_fasta`: FASTA file for the reference genome.

## Usage

1. Clone this repository:

   ```sh
   git clone <repository_url>
   cd <repository_directory>
   ```

2. Modify the parameters in the script to match your data and directories.

3. Run the pipeline with Nextflow:

   ```sh
   nextflow run main.nf
   ```

## Pipeline Steps

### Bowtie Index Building

This process builds a Bowtie index from the reference genome.

```nextflow
process bowtie_build {
    container "pegi3s/bowtie1:1.2.3"
    
    publishDir "${params.genome_path}", mode: 'copy', pattern: "meu_genoma_index.*"
    
    input:
    path file

    output:
    path "meu_genoma_index.*"

    script:
    bowtie-build ${file} meu_genoma_index
}
```

### UMI Extraction

This process extracts UMIs from the raw sequence reads.

```nextflow
process umiToolsExtract {
    container "jdelling7igfl/umi_tools:1.1.2"

    input:
    path file

    output:
    path "${file}_umi.fastq.gz"

    script:
    umi_tools extract --stdin=${file} --extract-method=regex --bc-pattern='.{17,75}(?P<discard_1>AACTGTAGGCACCATCAAT)(?P<umi_1>.{12})(?P<discard_2>AGATCGGAAGAGCACACGTCT)(?P<discard_3>.*)' --log=processed.log --stdout ${file}_umi.fastq.gz
}
```

### Alignment

This process aligns the sequence reads to the reference genome using Bowtie.

```nextflow
process bowtie {
    container "pegi3s/bowtie1:1.2.3"

    input:
    tuple path(file), val(index)

    output:
    path "${file}_mapped.sam"

    script:
    bowtie --threads 4 -v 2 -m 8 -a ${params.genome_path}/meu_genoma_index ${file} --sam ${file}_mapped.sam
}
```

### SAM to BAM Conversion

This process converts SAM files to BAM format using Samtools.

```nextflow
process samtoolsView {
    container "genomicpariscentre/samtools:1.4.1"

    input:
    path file

    output:
    path "${file}_mapped.bam"

    script:
    samtools view -bS -o ${file}_mapped.bam ${file}
}
```

### BAM Sorting

This process sorts BAM files using Samtools.

```nextflow
process samtoolsSort {
    container "genomicpariscentre/samtools:1.4.1"

    input:
    path file

    output:
    path "${file}_mapped_sorted.bam"

    script:
    samtools sort ${file} -o ${file}_mapped_sorted.bam
}
```

### BAM Indexing

This process indexes sorted BAM files using Samtools.

```nextflow
process samtoolsIndex {
    container "genomicpariscentre/samtools:1.4.1"

    input:
    path file

    output:
    path "${file}.bai"

    script:
    samtools index ${file}
}
```

### Deduplication

This process deduplicates BAM files using UMI-tools.

```nextflow
process umiToolsDedup {
    container "jdelling7igfl/umi_tools:1.1.2"

    input:
    path file
    path dummy

    output:
    path "${file}_deduplicated.bam"

    script:
    umi_tools dedup -I ${file} --output-stats=deduplicated -S ${file}_deduplicated.bam
}
```

### Feature Counting

This process counts features using featureCounts.

```nextflow
process featureCounts {
    container "pegi3s/feature-counts:2.0.0"

    input:
    path file

    output:
    path "${file}_featurecounts.txt"

    script:
    featureCounts -a ${params.genome_path}/${params.genome_gtf} -O -g 'transcript_id' -o ${file}_featurecounts.txt ${file}
}
```

### Quality Control

This process performs quality control checks using FastQC.

```nextflow
process fastqc_original {
    container "biocontainers/fastqc:v0.11.9_cv8"

    input:
    path file

    output:
    path "fastqc_output_original/*"

    script:
    mkdir fastqc_output_original
    fastqc ${file} -o fastqc_output_original
}

process fastqc_processado {
    container "biocontainers/fastqc:v0.11.9_cv8"

    input:
    path file

    output:
    path "fastqc_output_processado/*"

    script:
    mkdir fastqc_output_processado
    fastqc ${file} -o fastqc_output_processado
}
```

## Workflow

The main workflow orchestrates the entire process, chaining the steps together.

```nextflow
workflow {
    sequencesFiles_ch = Channel.fromPath(params.inputDir + "/*").flatten()
    genome_ch = Channel.fromPath(params.genome_path + "/*" + params.genoma_fasta).flatten()
    
    bowtie_build(genome_ch)

    umiExtracted_ch = umiToolsExtract(sequencesFiles_ch)
    umiExtracted_ch.collectFile (
        storeDir: "${params.outputDir}/umi_processados"
    )

    bowtie_build_index = bowtie_build.out.first()
    bowtieInputs_ch = umiExtracted_ch.map { file -> tuple(file, bowtie_build_index) }

    bowtieMapped_ch = bowtie(bowtieInputs_ch)
    bowtieMapped_ch.collectFile (
        storeDir: "${params.outputDir}/bowtie_mapeados"
    )   
    
    samView_ch = samtoolsView(bowtieMapped_ch)
    samView_ch.collectFile (
        storeDir: "${params.outputDir}/samtools_convertidos"
    )

    samSort_ch = samtoolsSort(samView_ch)
    samSort_ch.collectFile (
        storeDir: "${params.outputDir}/samtools_ordenados"
    )

    samIndex_ch = samtoolsIndex(samSort_ch)
    samIndex_ch.collectFile (
        storeDir: "${params.outputDir}/samtools_ordenados"
    )

    umiDedup_ch = umiToolsDedup(samSort_ch, samIndex_ch)
    umiDedup_ch.collectFile (
        storeDir: "${params.outputDir}/umi_dedup_output"
    )

    featureCounts_ch = featureCounts(umiDedup_ch)
    featureCounts_ch.collectFile (
        storeDir: "${params.outputDir}/featureCounts"
    )
}
```

## Notes

- Make sure that the input and reference genome directories are correctly set.
- Adjust the parameters as needed to match your specific requirements.

