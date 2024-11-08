#!/usr/bin/env nextflow
nextflow.enable.dsl=2

params.inputDir = "/mnt/d/Teste_Nextflow/arquivos_de_input"
params.outputDir = "/mnt/d/Teste_Nextflow"
params.genome_path = "/mnt/d/Teste_Nextflow/genoma_de_referencia"
params.genome_gtf = "genome_GTF.gtf" 
params.genoma_fasta = "genoma_FASTA.fna"

process bowtie_build {
    container "pegi3s/bowtie1:1.2.3"
    
    publishDir "${params.genome_path}", mode: 'copy', pattern: "meu_genoma_index.*"
    
    input:
    path file

    output:
    path "meu_genoma_index.*"

    """
    bowtie-build ${file} meu_genoma_index
    """
}

process umiToolsExtract {
    container "jdelling7igfl/umi_tools:1.1.2"

    input:
    path file

    output:
    path "${file}_umi.fastq.gz"

    """
    umi_tools extract --stdin=${file} --extract-method=regex --bc-pattern='.{17,75}(?P<discard_1>AACTGTAGGCACCATCAAT)(?P<umi_1>.{12})(?P<discard_2>AGATCGGAAGAGCACACGTCT)(?P<discard_3>.*)' --log=processed.log --stdout ${file}_umi.fastq.gz
    """
}

process bowtie {
    container "pegi3s/bowtie1:1.2.3"

    input:
    tuple path(file), val(index)

    output:
    path "${file}_mapped.sam"

    """
    bowtie --threads 4 -v 2 -m 8 -a ${params.genome_path}/meu_genoma_index ${file} --sam ${file}_mapped.sam
    """
}


process samtoolsView {
    container "genomicpariscentre/samtools:1.4.1"

    input:
    path file

    output:
    path "${file}_mapped.bam"

    """
    samtools view -bS -o ${file}_mapped.bam ${file}
    """
}

process samtoolsSort {
    container "genomicpariscentre/samtools:1.4.1"

    input:
    path file

    output:
    path "${file}_mapped_sorted.bam"

    """
    samtools sort ${file} -o ${file}_mapped_sorted.bam
    """
}

process samtoolsIndex {
    container "genomicpariscentre/samtools:1.4.1"

    input:
    path file

    output:
    path "${file}.bai"

    """
    samtools index ${file}
    """
}

process umiToolsDedup {
    container "jdelling7igfl/umi_tools:1.1.2"

    input:
    path file
    path dummy

    output:
    path "${file}_deduplicated.bam"

    """
    umi_tools dedup -I ${file} --output-stats=deduplicated -S ${file}_deduplicated.bam
    """
}

process featureCounts {
    container "pegi3s/feature-counts:2.0.0"

    input:
    path file

    output:
    path "${file}_featurecounts.txt"

    """
    featureCounts -a ${params.genome_path}/${params.genome_gtf} -O -g 'transcript_id' -o ${file}_featurecounts.txt ${file}
    """
}

process fastqc_original {
    container "biocontainers/fastqc:v0.11.9_cv8"

    input:
    path file

    output:
    path "fastqc_output_original/*"

    """
    mkdir fastqc_output_original
    fastqc ${file} -o fastqc_output_original
    """
}
process fastqc_processado {
    container "biocontainers/fastqc:v0.11.9_cv8"

    input:
    path file

    output:
    path "fastqc_output_processado/*"

    """
    mkdir fastqc_output_processado
    fastqc ${file} -o fastqc_output_processado
    """
}

workflow {

    sequencesFiles_ch = Channel.fromPath(params.inputDir + "/*").flatten()
    genome_ch = Channel.fromPath(params.genome_path + "/*" + params.genoma_fasta).flatten()
'''
    fastqcOutput_ch = fastqc_original(sequencesFiles_ch)
    fastqcOutput_ch.flatten().collectFile (
        storeDir: "${params.outputDir}/fastqc_output_original"
    )
'''
    bowtie_build(genome_ch)

    // Extract UMIs from the sequence files
    umiExtracted_ch = umiToolsExtract(sequencesFiles_ch)
    umiExtracted_ch.collectFile (
        storeDir: "${params.outputDir}/umi_processados"
    )

    bowtie_build_index = bowtie_build.out.first()
    bowtieInputs_ch = umiExtracted_ch.map { file -> tuple(file, bowtie_build_index) }

    // Align the sequences to the reference genome
    bowtieMapped_ch = bowtie(bowtieInputs_ch)
    bowtieMapped_ch.collectFile (
        storeDir: "${params.outputDir}/bowtie_mapeados"
    )   
'''
    fastqcOutputp_ch = fastqc_processado(umiExtracted_ch)
    fastqcOutputp_ch.flatten().collectFile (
        storeDir: "${params.outputDir}/fastqc_output_processado"
    )
'''
    // Convert SAM to BAM
    samView_ch = samtoolsView(bowtieMapped_ch)
    samView_ch.collectFile (
        storeDir: "${params.outputDir}/samtools_convertidos"
    )

    // Sort BAM files
    samSort_ch = samtoolsSort(samView_ch)
    samSort_ch.collectFile (
        storeDir: "${params.outputDir}/samtools_ordenados"
    )

    // Index sorted BAM files
    samIndex_ch = samtoolsIndex(samSort_ch)
    samIndex_ch.collectFile (
        storeDir: "${params.outputDir}/samtools_ordenados"
    )


    // Deduplicate BAM files
    umiDedup_ch = umiToolsDedup(samSort_ch, samIndex_ch)
    umiDedup_ch.collectFile (
        storeDir: "${params.outputDir}/umi_dedup_output"
    )

    // Count features
    featureCounts_ch = featureCounts(umiDedup_ch)
    featureCounts_ch.collectFile (
        storeDir: "${params.outputDir}/featureCounts"
    )

}
