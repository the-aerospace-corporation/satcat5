// Copyright 2020 The Aerospace Corporation
//
// This file is part of SatCat5.
//
// SatCat5 is free software: you can redistribute it and/or modify it under
// the terms of the GNU Lesser General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// SatCat5 is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
// License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.

pipeline {
    agent any

    options {
        timeout(time: 180, unit: 'MINUTES')
        disableConcurrentBuilds() // Prevent two concurrent runs
        parallelsAlwaysFailFast() // Fail as soon as any parallel stage fails
    }

    environment {
        VIVADO_VERSION = "2015.4"
    }

    stages {
        stage('Build-All') {
            parallel {
                stage('Sims') {
                    agent { label 'Vivado2015.4' }
                    steps { dir('.') { sh 'make sims' } }
                    post { success {
                        // junit has issues with paths, so soft-link it first
                        sh 'ln -s sim/vhdl/sim_results.xml $WORKSPACE'
                        junit 'sim_results.xml'
                        // Archive sim results
                        archiveArtifacts artifacts: 'sim/vhdl/xsim_tmp/simulate_*.log'
                    } }
                }
                stage('Arty-35T') {
                    agent { label 'Vivado2015.4' }
                    steps { dir('.') { sh 'make arty_35t' } }
                    post { success { archiveArtifacts artifacts: '**/*.rpt, **/switch_top_arty_a7_rmii.bit' } }
                }
                stage('AC701-SGMII') {
                    agent { label 'Vivado2015.4' }
                    steps { dir('.') { sh 'make proto_v1_sgmii' } }
                    post { success { archiveArtifacts artifacts: '**/*.rpt, **/switch_top_ac701_sgmii.bit' } }
                }
                stage('AC701-Router') {
                    agent { label 'Vivado2015.4' }
                    steps { dir('.') { sh 'make router_ac701' } }
                    post { success { archiveArtifacts artifacts: '**/*.rpt, **/router_ac701_wrapper.bit' } }
                }
            }
        }
    }
}
